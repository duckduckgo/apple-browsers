# frozen_string_literal: true

require "time"

# Works out the App Store entries of release_metadata.json from the live version's phased release state.
#
# `available_appstore_version` is the release that is rolling out, and `latest_appstore_version` is the
# release that has finished rolling out. Clients require `latest_appstore_version`, so it's never removed.
# While a rollout is paused its entry moves to `paused_appstore_version`, which clients ignore, so that
# resuming or completing the rollout keeps its release date and critical flag.
module AppStoreReleaseMetadata
  LATEST_KEY = "latest_appstore_version"
  AVAILABLE_KEY = "available_appstore_version"
  PAUSED_KEY = "paused_appstore_version"

  module PhaseState
    INACTIVE = "INACTIVE"
    ACTIVE = "ACTIVE"
    PAUSED = "PAUSED"
    COMPLETE = "COMPLETE"
  end

  class Error < StandardError; end

  # @param existing [Hash] The current contents of release_metadata.json, or an empty hash if there's none.
  # @param version [String] The live App Store version.
  # @param build_number [Integer] The live App Store build number.
  # @param phase_state [String, nil] The live version's phased release state, or nil if it was released
  #   without a phased release.
  # @param phase_start_date [String, nil] The phased release's start date, as returned by App Store Connect.
  # @param is_critical [Boolean, nil] Whether the release is critical, or nil to keep the existing value.
  # @param now [Time]
  # @return [Hash] The updated contents of release_metadata.json.
  def self.update(existing, version:, build_number:, phase_state:, phase_start_date:, is_critical:, now:)
    release = { "latest_version" => version, "build_number" => Integer(build_number) }
    start_date = phase_start_date ? format_date(Time.iso8601(phase_start_date)) : nil
    metadata = existing.dup

    default_date = start_date || format_date(now)

    rolling_out = [existing[AVAILABLE_KEY], existing[PAUSED_KEY]]

    case phase_state
    when PhaseState::ACTIVE, PhaseState::PAUSED
      key, other_key = phase_state == PhaseState::ACTIVE ? [AVAILABLE_KEY, PAUSED_KEY] : [PAUSED_KEY, AVAILABLE_KEY]
      metadata.delete(other_key)
      if newer?(release, metadata[LATEST_KEY])
        metadata[key] = entry(release, rolling_out, default_date, is_critical)
      else
        metadata.delete(key)
      end
    when PhaseState::COMPLETE, nil
      metadata[LATEST_KEY] = entry(release, [existing[LATEST_KEY], *rolling_out], default_date, is_critical)
      metadata.delete(AVAILABLE_KEY) unless newer?(metadata[AVAILABLE_KEY], metadata[LATEST_KEY])
      metadata.delete(PAUSED_KEY)
    when PhaseState::INACTIVE
      nil
    else
      raise Error, "Unknown phased release state: #{phase_state}"
    end

    raise Error, "#{LATEST_KEY} is missing, so clients couldn't read the file" unless metadata[LATEST_KEY]

    metadata
  end

  # Reuses the release date and critical flag of a previous entry for the same release, so reruns don't
  # change them.
  def self.entry(release, previous, release_date, is_critical)
    match = previous.compact.find { |candidate| same_release?(candidate, release) }
    release.merge(
      "release_date" => match ? match["release_date"] : release_date,
      "is_critical" => is_critical.nil? ? (match ? match["is_critical"] : false) : is_critical
    )
  end

  def self.same_release?(lhs, rhs)
    lhs["latest_version"] == rhs["latest_version"] && lhs["build_number"] == rhs["build_number"]
  end

  # Matches the client, which compares versions numerically and then build numbers.
  def self.newer?(release, other)
    return false unless release
    return true unless other

    comparison = Gem::Version.new(release["latest_version"]) <=> Gem::Version.new(other["latest_version"])
    comparison.zero? ? release["build_number"] > other["build_number"] : comparison.positive?
  end

  # Clients parse dates with ISO8601DateFormatter's default options, which don't accept fractional seconds.
  def self.format_date(time)
    time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  private_class_method :entry, :same_release?, :newer?, :format_date
end

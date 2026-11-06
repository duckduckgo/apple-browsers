# frozen_string_literal: true

require "minitest/autorun"
require_relative "../appstore_release_metadata"

class AppStoreReleaseMetadataTest < Minitest::Test
  NOW = Time.utc(2026, 1, 7, 12, 30, 0)
  START_DATE = "2026-01-05T08:00:00-08:00"
  START_DATE_UTC = "2026-01-05T16:00:00Z"

  LATEST = {
    "latest_version" => "1.100.0",
    "build_number" => 500,
    "release_date" => "2025-12-29T16:00:00Z",
    "is_critical" => false
  }.freeze

  OTHER_KEYS = { "latest_ios_version" => { "latest_version" => "7.200.0" } }.freeze

  def update(existing, version: "1.101.0", build_number: 510, phase_state:, phase_start_date: START_DATE,
             is_critical: nil)
    AppStoreReleaseMetadata.update(existing, version: version, build_number: build_number,
                                             phase_state: phase_state, phase_start_date: phase_start_date,
                                             is_critical: is_critical, now: NOW)
  end

  def release(version: "1.101.0", build_number: 510, release_date: START_DATE_UTC, is_critical: false)
    {
      "latest_version" => version,
      "build_number" => build_number,
      "release_date" => release_date,
      "is_critical" => is_critical
    }
  end

  def existing(**entries)
    { "latest_appstore_version" => LATEST }.merge(OTHER_KEYS).merge(entries.transform_keys(&:to_s))
  end

  # ACTIVE

  def test_active_publishes_available_release_dated_from_rollout_start
    result = update(existing, phase_state: "ACTIVE")

    assert_equal existing.merge("available_appstore_version" => release), result
  end

  def test_active_publishes_critical_release
    result = update(existing, phase_state: "ACTIVE", is_critical: true)

    assert_equal release(is_critical: true), result["available_appstore_version"]
  end

  def test_active_rerun_keeps_release_date_and_critical_flag
    previous = release(release_date: "2026-01-05T17:00:00Z", is_critical: true)

    result = update(existing(available_appstore_version: previous), phase_state: "ACTIVE")

    assert_equal previous, result["available_appstore_version"]
  end

  def test_active_rerun_can_change_critical_flag
    previous = release(is_critical: true)

    result = update(existing(available_appstore_version: previous), phase_state: "ACTIVE", is_critical: false)

    assert_equal release(is_critical: false), result["available_appstore_version"]
  end

  def test_active_replaces_available_entry_for_another_release
    previous = release(version: "1.100.1", build_number: 505, release_date: "2026-01-01T00:00:00Z", is_critical: true)

    result = update(existing(available_appstore_version: previous), phase_state: "ACTIVE")

    assert_equal release, result["available_appstore_version"]
  end

  def test_active_newer_build_of_same_version_is_published
    result = update(existing, version: "1.100.0", build_number: 501, phase_state: "ACTIVE")

    assert_equal release(version: "1.100.0", build_number: 501), result["available_appstore_version"]
  end

  def test_active_release_that_is_not_newer_than_latest_is_not_published
    stale = release(version: "1.100.0", build_number: 500)

    result = update(existing(available_appstore_version: stale), version: "1.100.0", build_number: 500,
                                                                 phase_state: "ACTIVE")

    assert_equal existing, result
  end

  def test_active_compares_versions_numerically
    result = update(existing, version: "1.99.0", phase_state: "ACTIVE")

    refute result.key?("available_appstore_version")
  end

  def test_resuming_republishes_release_dated_from_rollout_start
    result = update(existing, phase_state: "ACTIVE", is_critical: true)

    assert_equal existing(available_appstore_version: release(is_critical: true)), result
  end

  def test_active_without_start_date_uses_current_time
    result = update(existing, phase_state: "ACTIVE", phase_start_date: nil)

    assert_equal release(release_date: "2026-01-07T12:30:00Z"), result["available_appstore_version"]
  end

  def test_active_without_latest_entry_fails
    assert_raises(AppStoreReleaseMetadata::Error) { update({}, phase_state: "ACTIVE") }
  end

  # PAUSED

  def test_paused_withdraws_available_release
    available = release(is_critical: true)

    result = update(existing(available_appstore_version: available), phase_state: "PAUSED")

    assert_equal existing, result
  end

  def test_paused_rerun_changes_nothing
    result = update(existing, phase_state: "PAUSED")

    assert_equal existing, result
  end

  # COMPLETE

  def test_complete_promotes_available_release_to_latest
    available = release(is_critical: true)

    result = update(existing(available_appstore_version: available), phase_state: "COMPLETE")

    assert_equal OTHER_KEYS.merge("latest_appstore_version" => available), result
  end

  def test_complete_without_previous_entry_is_dated_from_rollout_start
    result = update(existing, phase_state: "COMPLETE")

    assert_equal OTHER_KEYS.merge("latest_appstore_version" => release), result
  end

  def test_complete_rerun_keeps_latest_entry
    latest = release(release_date: "2026-01-05T17:00:00Z", is_critical: true)

    result = update(existing.merge("latest_appstore_version" => latest), phase_state: "COMPLETE")

    assert_equal OTHER_KEYS.merge("latest_appstore_version" => latest), result
  end

  def test_complete_keeps_newer_available_release
    newer = release(version: "1.102.0", build_number: 520)

    result = update(existing(available_appstore_version: newer), phase_state: "COMPLETE")

    assert_equal OTHER_KEYS.merge("latest_appstore_version" => release, "available_appstore_version" => newer), result
  end

  def test_complete_creates_file_when_there_is_none
    result = update({}, phase_state: "COMPLETE")

    assert_equal({ "latest_appstore_version" => release }, result)
  end

  def test_release_without_phased_release_is_latest_dated_now
    result = update(existing, phase_state: nil, phase_start_date: nil, is_critical: true)

    assert_equal release(release_date: "2026-01-07T12:30:00Z", is_critical: true), result["latest_appstore_version"]
  end

  # INACTIVE and unknown states

  def test_inactive_changes_nothing
    available = release

    result = update(existing(available_appstore_version: available), phase_state: "INACTIVE")

    assert_equal existing(available_appstore_version: available), result
  end

  def test_unknown_state_fails
    assert_raises(AppStoreReleaseMetadata::Error) { update(existing, phase_state: "SOMETHING_NEW") }
  end

  def test_does_not_modify_existing_hash
    original = existing(available_appstore_version: release)
    snapshot = Marshal.load(Marshal.dump(original))

    update(original, phase_state: "COMPLETE")

    assert_equal snapshot, original
  end
end

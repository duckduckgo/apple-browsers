# Dangerfile example
if git.added_files.any? { |file| file.include?("Assets.xcassets") && file.include?("colorset") }
  fail("🚨 New colors detected in asset catalog. Use DesignResourcesKit instead!")
end


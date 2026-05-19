require 'xcodeproj'
project_path = 'CinematicCoreMacOS/CinematicCoreMacOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'CinematicCoreMacOS' }
group = project.main_group.find_subpath('CinematicCoreMacOS', true)

# Add files
h_file = group.new_file('DeckLinkOutputBridge.h')
mm_file = group.new_file('DeckLinkOutputBridge.mm')
bridging_file = group.new_file('CinematicCoreMacOS-Bridging-Header.h')

# Add mm file to build phase
target.source_build_phase.add_file_reference(mm_file)

# Set bridging header in build settings
target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'CinematicCoreMacOS/CinematicCoreMacOS-Bridging-Header.h'
end

project.save
puts "Successfully updated Xcode project."

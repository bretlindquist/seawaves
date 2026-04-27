require 'xcodeproj'
project_path = 'SeaWaves/SeaWaves.xcodeproj'
project = Xcodeproj::Project.open(project_path)

group = project.main_group.find_subpath('Sources', false)

file_ref = group.new_reference('Localizable.xcstrings')

target = project.targets.first
target.add_file_references([file_ref])

project.save

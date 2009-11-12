require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "juggler"
    gemspec.summary = "Handles exceptions in rails apps, rendering error " +
                      "pages and emailing when exceptions occur"
    gemspec.description = <<-DESC 

      To Do write description

    DESC
    gemspec.email = "percivalatumamibuddotcom"
    gemspec.homepage = "http://github.com/bmpercy/juggler"
    gemspec.authors = ['Brian Percival']
    gemspec.add_dependency 'actionmailer'
    gemspec.files = ["juggler.gemspec",
                     "[A-Z]*.*",
                     "lib/**/*.rb",
                     "views/**/*",
                     "rails/**/*"]
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

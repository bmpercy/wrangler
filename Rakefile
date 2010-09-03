require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "wrangler"
    gemspec.summary = "Handles exceptions in rails apps, rendering error pages and emailing when exceptions occur. Spun off from some work at discovereads.com"
    gemspec.description = <<-DESC 
A gem for handling exceptions thrown inside your Rails app. If you include the
gem in your application controller, wrangler will render the error pages you
configure for each exception or HTTP error code. It will also handle notifying
you via email when certain exceptions are raised. Allows for configuration of
which exceptions map to which error pages, which exceptions result in emails
being sent. Also allows for asynchronous email sending via delayed job so that
error pages don't take forever to load (but delayed_job is not required for
sending email; wrangler will automatically send email synchronously if
delayed_job is not available. . See README for lots of info on how to
get started and what configuration options are available.
DESC
    gemspec.email = "percivalatumamibuddotcom"
    gemspec.homepage = "http://github.com/bmpercy/wrangler"
    gemspec.authors = ['Brian Percival']
# TODO: this dependency causes all sorts of problems with extra gem installs
#       (like the latest rails every new release). also add_dependency is
#       deprecated
#    gemspec.add_dependency 'actionmailer', '>= 2.1.0'
    gemspec.files = ["wrangler.gemspec",
                     "[A-Z]*.*",
                     "lib/**/*.rb",
                     "views/**/*",
                     "rails/**/*"]
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

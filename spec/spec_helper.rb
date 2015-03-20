# test dependencies
require 'json'

# java dependencies
java_libs = Dir["spec/lib/**/*.jar"]

# the rest of the application
model_files = %W(models/exceptions models/values models/services models/use_cases)

if RUBY_PLATFORM == 'java'

  java_libs.each do |jar|
    require jar
  end

  model_files.each do |autoload_path|
    Dir[File.expand_path("../../#{autoload_path}/**/*.rb", __FILE__)].each { |f| require f }
  end

end

# supporting ruby files with custom matchers and macros, etc,
# in spec/support/ and its subdirectories.
Dir[File.expand_path('../support/**/*.rb', __FILE__)].each { |f| require f }

RSpec.configure do |config|
  # disable should syntax, it wil become obsolete in future RSpec releases
  # http://myronmars.to/n/dev-blog/2012/06/rspecs-new-expectation-syntax
  config.expect_with :rspec do |c|
    c.syntax = [:expect]
  end

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = "random"

  config.raise_errors_for_deprecations!
end

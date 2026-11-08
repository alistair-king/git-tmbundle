require 'minitest/autorun'
require 'shellwords'
require 'erb'
require_relative '../tmvc/lib/format_helpers/tag_helper'
require_relative '../tmvc/lib/html_helpers'
require_relative '../tmvc/lib/application_helper'
require_relative '../tmvc/lib/application_controller'
require_relative '../lib/date_helpers'
require_relative '../app/controllers/annotate_controller'

class AnnotateControllerTest < Minitest::Test
  class Controller < AnnotateController
    attr_reader :calls, :renders, :messages
    def initialize
      super
      @calls, @renders, @messages = [], [], []
    end
    def git; self; end
    def annotate(*args); @calls << args; []; end
    def log(options); []; end
    def render(*args); @renders << args; end
    def puts(message); @messages << message; end
  end

  def setup
    @saved_env = ENV.to_hash
    ENV.delete('TM_FILEPATH')
    ENV.delete('TM_SELECTED_FILES')
    @controller = Controller.new
  end

  def teardown
    ENV.replace(@saved_env)
  end

  def test_missing_file_shows_message_without_running_git
    @controller.index
    assert_empty @controller.calls
    assert_match(/Choose a file/, @controller.messages.join)
  end

  def test_explicit_path_takes_precedence_over_current_file
    ENV['TM_FILEPATH'] = '/repo/other.rb'
    @controller.params = {:file_path => '/repo/chosen.rb'}
    @controller.index
    assert_equal [['/repo/chosen.rb']], @controller.calls
  end

  def test_current_file
    ENV['TM_FILEPATH'] = '/repo/current.rb'
    @controller.index
    assert_equal [['/repo/current.rb']], @controller.calls
  end

  def test_selected_file_with_spaces
    ENV['TM_SELECTED_FILES'] = Shellwords.join(['/repo/file with spaces.rb'])
    @controller.index
    assert_equal [['/repo/file with spaces.rb']], @controller.calls
  end

  def test_multiple_selected_files_are_rejected
    ENV['TM_SELECTED_FILES'] = '/repo/one.rb /repo/two.rb'
    @controller.index
    assert_empty @controller.calls
  end

  def test_directory_is_rejected
    @controller.params = {:file_path => File.dirname(__FILE__)}
    @controller.index
    assert_empty @controller.calls
  end

  def test_revision_updates_keep_explicit_file_and_render_partial
    @controller.params = {:file_path => '/repo/selected.rb', :revision => 'abc123'}
    @controller.update
    assert_equal [['/repo/selected.rb', 'abc123']], @controller.calls
    assert_equal true, @controller.instance_variable_get(:@as_partial)
    assert_equal '_content', @controller.renders.first.first
  end
end

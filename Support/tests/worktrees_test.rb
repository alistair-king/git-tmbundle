# encoding: utf-8
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require_relative '../worktrees'

class GitWorktreesTest < Minitest::Test
  def setup
    @temporary = File.realpath(Dir.mktmpdir('textmate-worktrees-'))
    @root = File.join(@temporary, 'main checkout')
    FileUtils.mkdir_p(@root)
    git('init', '-b', 'main')
    git('config', 'user.name', 'Worktree Test')
    git('config', 'user.email', 'worktree@example.invalid')
    git('config', 'commit.gpgsign', 'false')
    File.write(File.join(@root, 'file.txt'), "original\n")
    git('add', '.')
    git('commit', '-m', 'Initial')
    @repository = GitWorktrees::Repository.new(@root, 'git')
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def git(*arguments)
    output, error, status = Open3.capture3('git', '-C', @root, *arguments)
    raise error unless status.success?
    output
  end

  def test_discovers_main_and_linked_worktrees_from_either_checkout
    destination = File.join(@temporary, "linked space é\ncheckout")
    @repository.create(destination, :new, 'feature/task')
    linked = GitWorktrees::Repository.new(destination, 'git')
    assert_equal @repository.list, linked.list
    assert_equal destination, linked.root
    assert_equal 'refs/heads/feature/task', linked.list.last['branch']
  end

  def test_creates_new_branch_without_switching_current_checkout
    destination = @repository.create('new checkout', :new, 'feature/new')
    assert_equal File.join(@temporary, 'new checkout'), destination
    assert_equal 'main', git('branch', '--show-current').strip
    assert File.file?(File.join(destination, 'file.txt'))
  end

  def test_creates_existing_branch_and_excludes_occupied_branches
    git('branch', 'available')
    assert_equal ['available'], @repository.branches
    @repository.create(File.join(@temporary, 'existing'), :existing, 'available')
    assert_empty @repository.branches
    assert_raises(GitWorktrees::Error) { @repository.create(File.join(@temporary, 'other'), :existing, 'available') }
  end

  def test_detached_revision_and_invalid_revision
    @repository.create(File.join(@temporary, 'detached'), :detached, 'HEAD')
    assert @repository.list.last['detached']
    assert_raises(GitWorktrees::Error) { @repository.create(File.join(@temporary, 'invalid'), :detached, 'no-such-revision') }
  end

  def test_refuses_existing_destination_and_option_like_branch
    assert_raises(GitWorktrees::Error) { @repository.create(@root, :new, 'feature') }
    assert_raises(GitWorktrees::Error) { @repository.create(File.join(@temporary, 'bad'), :new, '--force') }
  end

  def test_dirty_and_untracked_worktrees_cannot_be_removed
    path = @repository.create('dirty', :new, 'dirty')
    File.write(File.join(path, 'file.txt'), "modified\n")
    assert_raises(GitWorktrees::Error) { @repository.remove(path) }
    File.write(File.join(path, 'file.txt'), "original\n")
    File.write(File.join(path, 'untracked'), 'keep me')
    assert_raises(GitWorktrees::Error) { @repository.remove(path) }
    assert File.directory?(path)
  end

  def test_clean_removal_keeps_branch
    path = @repository.create('clean', :new, 'keep-branch')
    @repository.remove(path)
    refute File.exist?(path)
    assert_includes @repository.branches, 'keep-branch'
  end

  def test_main_current_and_locked_worktrees_are_protected
    path = @repository.create('locked', :new, 'locked')
    git('worktree', 'lock', '--reason', 'Keep this checkout', path)
    assert_empty @repository.removable
    assert_raises(GitWorktrees::Error) { @repository.remove(path) }
    assert_raises(GitWorktrees::Error) { @repository.remove(@root) }
    git('worktree', 'unlock', path)
    linked = GitWorktrees::Repository.new(path, 'git')
    assert_empty linked.removable
    assert_raises(GitWorktrees::Error) { linked.remove(path) }
  end

  def test_inherited_git_overrides_do_not_redirect_commands
    previous = ENV.to_h.select { |key, _| key.start_with?('GIT_') }
    ENV['GIT_DIR'] = File.join(@temporary, 'nonexistent')
    ENV['GIT_WORK_TREE'] = @temporary
    ENV['GIT_INDEX_FILE'] = File.join(@temporary, 'wrong-index')
    assert_equal @root, GitWorktrees::Repository.new(@root, 'git').root
    @repository.create('isolated', :new, 'isolated')
    refute File.exist?(ENV['GIT_INDEX_FILE'])
  ensure
    ENV.keys.grep(/\AGIT_/).each { |key| ENV.delete(key) }
    previous.each { |key, value| ENV[key] = value }
  end

  def test_parser_preserves_spaces_newlines_and_lock_reasons
    output = "worktree /tmp/main\0HEAD abc\0branch refs/heads/main\0\0worktree /tmp/a\nb c\0HEAD def\0detached\0locked reason with spaces\0\0"
    entries = GitWorktrees::Repository.parse_list(output)
    assert_equal 2, entries.size
    assert_equal "/tmp/a\nb c", entries.last['worktree']
    assert_equal 'reason with spaces', entries.last['locked']
  end

  class CancelUI
    def menu(_items); nil; end
  end

  def test_list_reports_checkouts_and_escapes_html
    path = @repository.create('checkout <script> & space', :new, 'feature/<review>')
    output, = capture_io { GitWorktrees::Commands.new(@repository, CancelUI.new).list }
    assert_includes output, 'Main; Current'
    assert_includes output, 'feature/&lt;review&gt;'
    assert_includes output, CGI.escapeHTML(path)
    refute_includes output, '<script>'
    assert_includes output, git('rev-parse', 'HEAD').strip
    assert_equal 2, @repository.list.size
    assert_equal 'main', git('branch', '--show-current').strip
  end

  def test_list_includes_detached_locked_and_missing_worktrees
    path = @repository.create('locked report', :detached, 'HEAD')
    git('worktree', 'lock', '--reason', 'Keep <this>', path)
    missing = @repository.create('missing report', :new, 'missing-report')
    FileUtils.remove_entry(missing)
    output, = capture_io { GitWorktrees::Commands.new(@repository, CancelUI.new).list }
    assert_includes output, 'Detached HEAD'
    assert_includes output, 'Locked: Keep &lt;this&gt;'
    assert_includes output, 'Missing / prunable'
    assert_includes output, missing
  end

  def test_cancelling_open_and_create_does_nothing
    commands = GitWorktrees::Commands.new(@repository, CancelUI.new)
    commands.open
    commands.create
    assert_equal 1, @repository.list.size
  end

  def test_cancelling_remove_keeps_checkout
    path = @repository.create('cancel removal', :new, 'cancel-removal')
    ui = Object.new
    ui.define_singleton_method(:menu) { |_items| 0 }
    ui.define_singleton_method(:request_confirmation) { |_options| false }
    GitWorktrees::Commands.new(@repository, ui).remove
    assert File.directory?(path)
    assert_equal 2, @repository.list.size
  end

  def test_paths_and_revisions_are_passed_as_arguments
    path = File.join(@temporary, 'checkout; $(touch SHOULD_NOT_EXIST)')
    @repository.create(path, :new, 'literal-path')
    assert File.file?(File.join(path, 'file.txt'))
    refute File.exist?(File.join(@root, 'SHOULD_NOT_EXIST'))
    assert_raises(GitWorktrees::Error) do
      @repository.create('bad revision', :detached, 'HEAD; touch SHOULD_NOT_EXIST')
    end
    refute File.exist?(File.join(@root, 'SHOULD_NOT_EXIST'))
  end

  def test_open_does_not_inherit_originating_project_uuid
    destination = @repository.create('open target', :new, 'open-target')
    commands = GitWorktrees::Commands.new(@repository, CancelUI.new)
    calls = []
    commands.define_singleton_method(:system) { |*args| calls << args; true }
    previous = ENV['TM_MATE']
    ENV['TM_MATE'] = '/path with spaces/mate'
    capture_io { commands.open_path(destination) }
    assert_equal [{ 'TM_PROJECT_UUID' => nil }, '/path with spaces/mate', '--async', '--', destination], calls.fetch(0)
  ensure
    ENV['TM_MATE'] = previous
  end
end

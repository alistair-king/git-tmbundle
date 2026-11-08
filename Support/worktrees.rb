# encoding: utf-8
require 'open3'
require 'cgi'

module GitWorktrees
  class Error < StandardError; end

  class Repository
    attr_reader :root

    def initialize(directory, git = ENV.fetch('TM_GIT', 'git'))
      @directory, @git = directory, git
      @root = run('rev-parse', '--show-toplevel').sub(/\n\z/, '')
    end

    def run(*arguments)
      # A bundle command must address its own project, even when TextMate was
      # launched from a shell with Git overrides (including a temporary index).
      environment = ENV.keys.grep(/\AGIT_/).each_with_object({}) { |key, env| env[key] = nil }
      environment['GIT_TERMINAL_PROMPT'] = '0'
      output, error, status = Open3.capture3(environment, @git, '-C', @directory, *arguments)
      raise Error, error.strip.empty? ? 'Git could not complete the operation.' : error.strip unless status.success?
      output
    rescue Errno::ENOENT => error
      raise Error, "Git or the project directory was not found: #{error.message}"
    end

    def self.parse_list(output)
      entries, entry = [], {}
      output.split("\0", -1).each do |field|
        if field.empty?
          entries << entry unless entry.empty?
          entry = {}
        else
          key, value = field.split(' ', 2)
          entry[key] = value || true
        end
      end
      entries << entry unless entry.empty?
      entries
    end

    def list
      self.class.parse_list(run('worktree', 'list', '--porcelain', '-z'))
    end

    def same_path?(left, right)
      File.realpath(left) == File.realpath(right)
    rescue Errno::ENOENT
      File.expand_path(left) == File.expand_path(right)
    end

    def branches
      occupied = list.map { |entry| entry['branch'] }.compact
      run('for-each-ref', '--format=%(refname)', 'refs/heads/').lines.map(&:chomp).
        reject { |ref| occupied.include?(ref) }.map { |ref| ref.sub(%r{\Arefs/heads/}, '') }
    end

    def create(path, mode, revision)
      path = File.expand_path(path, File.dirname(root))
      raise Error, 'Choose a destination that does not already exist.' if File.exist?(path) || File.symlink?(path)
      raise Error, 'Enter a branch name or commit.' if revision.empty? || revision.start_with?('-')
      arguments = case mode
      when :new
        run('check-ref-format', '--branch', revision)
        ['-b', revision, '--', path, 'HEAD']
      when :existing
        raise Error, 'That branch is unavailable or is already checked out.' unless branches.include?(revision)
        ['--', path, revision]
      when :detached
        commit = run('rev-parse', '--verify', '--end-of-options', "#{revision}^{commit}").strip
        ['--detach', '--', path, commit]
      else
        raise Error, 'Unknown worktree creation mode.'
      end
      run('worktree', 'add', *arguments)
      path
    end

    def removable
      list.drop(1).reject { |entry| entry['locked'] || entry['prunable'] || same_path?(entry['worktree'], root) }
    end

    def remove(path)
      raise Error, 'The main, current, locked, or missing worktree cannot be removed here.' unless removable.any? { |entry| same_path?(entry['worktree'], path) }
      # Never force: Git refuses tracked changes and untracked files.
      run('worktree', 'remove', '--', path)
    end
  end

  class Commands
    def initialize(repository, ui)
      @repository, @ui = repository, ui
    end

    def label(entry)
      branch = entry['branch']&.sub(%r{\Arefs/heads/}, '') || (entry['bare'] ? 'bare repository' : 'detached HEAD')
      flags = []
      flags << 'current' if @repository.same_path?(entry['worktree'], @repository.root)
      flags << 'locked' if entry['locked']
      flags << 'missing' if entry['prunable']
      "#{branch} — #{entry['worktree']}#{flags.empty? ? '' : " [#{flags.join(', ')}]"}"
    end

    def choose(entries)
      raise Error, 'There are no eligible worktrees.' if entries.empty?
      index = @ui.menu(entries.map { |entry| label(entry) })
      index.nil? ? nil : entries.fetch(index)
    end

    def open_path(path)
      raise Error, 'The worktree directory is missing.' unless File.directory?(path)
      mate = ENV['TM_MATE'] || File.join(ENV.fetch('TM_APP_PATH'), 'Contents/MacOS/mate')
      # The originating project UUID would otherwise route this directory back
      # into the current window. Let mate resolve the destination project.
      success = system({ 'TM_PROJECT_UUID' => nil }, mate, '--async', '--', path)
      raise Error, "The worktree exists at #{path}, but TextMate could not open it." unless success
      puts "Opened #{path}"
    end

    def open
      entry = choose(@repository.list.reject { |item| item['bare'] || item['prunable'] })
      open_path(entry['worktree']) if entry
    end

    def list
      rows = @repository.list.each_with_index.map do |entry, index|
        branch = entry['branch']&.sub(%r{\Arefs/heads/}, '') || (entry['bare'] ? 'Bare repository' : 'Detached HEAD')
        flags = []
        flags << 'Main' if index.zero?
        flags << 'Current' if @repository.same_path?(entry['worktree'], @repository.root)
        ['locked', 'prunable'].each do |key|
          next unless entry[key]
          title = key == 'locked' ? 'Locked' : 'Missing / prunable'
          flags << (entry[key].is_a?(String) ? "#{title}: #{entry[key]}" : title)
        end
        cells = [branch, entry['worktree'], entry['HEAD'] || '', flags.join('; ')]
        '<tr>' + cells.map { |cell| "<td>#{CGI.escapeHTML(cell)}</td>" }.join + '</tr>'
      end
      puts <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>Git Worktrees</title>
        <style>
          :root { color-scheme: light dark; }
          body { font: 13px -apple-system, sans-serif; padding: 16px; }
          table { border-collapse: collapse; width: 100%; }
          th, td { text-align: left; vertical-align: top; padding: 8px; border-bottom: 1px solid #8886; }
          td { white-space: pre-wrap; overflow-wrap: anywhere; }
        </style></head><body><h1>Git Worktrees</h1>
        <table><thead><tr><th>Branch</th><th>Directory</th><th>Commit</th><th>Status</th></tr></thead>
        <tbody>#{rows.join("\n")}</tbody></table></body></html>
      HTML
    end

    def create
      index = @ui.menu(['New branch from HEAD', 'Existing local branch', 'Detached checkout of a commit or tag'])
      return if index.nil?
      mode = [:new, :existing, :detached].fetch(index)
      revision = if mode == :existing
        branches = @repository.branches
        raise Error, 'All local branches are already checked out, or there are no local branches.' if branches.empty?
        choice = @ui.menu(branches)
        return if choice.nil?
        branches.fetch(choice)
      else
        @ui.request_string(:title => 'Create Worktree', :prompt => mode == :new ? 'New branch name:' : 'Commit, branch, or tag:', :default => mode == :new ? '' : 'HEAD')
      end
      return if revision.nil?
      suffix = revision.gsub(/[^a-zA-Z0-9._-]+/, '-')
      destination = @ui.request_string(:title => 'Create Worktree', :prompt => 'Destination directory (relative paths are beside the current checkout):', :default => File.join(File.dirname(@repository.root), "#{File.basename(@repository.root)}-#{suffix}"))
      return if destination.nil?
      raise Error, 'Enter a destination directory.' if destination.empty?
      open_path(@repository.create(File.expand_path(destination, File.dirname(@repository.root)), mode, revision))
    end

    def remove
      entry = choose(@repository.removable)
      return unless entry
      confirmed = @ui.request_confirmation(:title => 'Remove Worktree?', :prompt => "Remove #{entry['worktree']} and its directory?\n\nSave and close its editor windows and terminals first. This command cannot detect unsaved buffers in other windows. Ignored files in this directory will also be deleted. The branch will be kept; Git will refuse changes or untracked files.", :button1 => 'Remove Worktree')
      return unless confirmed
      @repository.remove(entry['worktree'])
      puts "Removed #{entry['worktree']}. The branch was kept."
    end
  end

  def self.main(action)
    require "#{ENV.fetch('TM_SUPPORT_PATH')}/lib/ui"
    directory = ENV['TM_PROJECT_DIRECTORY'] || ENV['TM_DIRECTORY'] || (File.dirname(ENV['TM_FILEPATH']) if ENV['TM_FILEPATH']) || Dir.pwd
    Commands.new(Repository.new(directory), TextMate::UI).public_send(action)
  rescue Error, SystemCallError => error
    TextMate::UI.alert(:warning, 'Git Worktrees', error.message, 'OK')
  end
end

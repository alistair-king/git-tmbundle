# encoding: utf-8

class AnnotateController < ApplicationController
  include DateHelpers
  layout "application", :except => "update"
  def index
    return unless resolve_file_path
    @annotations = git.annotate(@file_path)

    if @annotations.nil?
      puts "Error.  Aborting"
      abort
    end

    @log_entries = git.log(:path => @file_path)
    render "index"
  end
  
  def update
    return unless resolve_file_path
    revision = params[:revision]

    @annotations = git.annotate(@file_path, revision)

    if @annotations.nil?
      puts "Error.  Aborting"
      abort
    end
    
      # f = Formatters::Annotate.new(:selected_revision => revision, :as_partial => true)
      # f.header "Annotations for ‘#{htmlize(shorten(file_path))}’"
      # f.content annotations
     @as_partial = true
     render "_content", :locals => { :annotations => @annotations, :revision => revision } 
     render "_select_revision", :locals => { :revision => revision}
  end

  private

  def resolve_file_path
    @file_path = [params[:file_path], ENV['TM_FILEPATH']].find { |path| path && !path.empty? }
    unless @file_path
      selected = Shellwords.shellwords(ENV['TM_SELECTED_FILES'].to_s)
      @file_path = selected.first if selected.length == 1
    end
    if !@file_path || File.directory?(@file_path)
      puts '<h2>Choose a file to annotate</h2><p>Open a saved file or select a single file in the project browser, then run Browse Annotated File (Blame) again.</p>'
      return false
    end
    true
  end
end

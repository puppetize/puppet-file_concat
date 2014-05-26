#
# TODO
#

require 'puppet/type/file'
require 'puppet/type/file/owner'
require 'puppet/type/file/group'
require 'puppet/type/file/mode'
require 'puppet/util/checksums'

Puppet::Type.newtype(:file_concat) do
  @doc = "TODO"

  ensurable

  # the file/posix provider will check for the :links property
  # which does not exist
  def [](value)
    if value == :links
      return false
    end

    super
  end

  newparam(:path, :namevar => true) do
    desc "Path to the file."
  end

  newproperty(:owner, :parent => Puppet::Type::File::Owner) do
    desc "Desired file owner."
  end

  newproperty(:group, :parent => Puppet::Type::File::Group) do
    desc "Desired file group."
  end

  # Autorequire the owner and group of the file.
  {:user => :owner, :group => :group}.each do |type, property|
    autorequire(type) do
      if @parameters.include?(property)
        # The user/group property automatically converts to IDs
        next unless should = @parameters[property].shouldorig
        val = should[0]
        if val.is_a?(Integer) or val =~ /^\d+$/
          nil
        else
          val
        end
      end
    end
  end

  newproperty(:mode, :parent => Puppet::Type::File::Mode) do
    desc "Desired file mode."
  end

  newproperty(:content) do
    desc "Read only attribute. Represents the content."

    include Puppet::Util::Diff
    include Puppet::Util::Checksums

    defaultto do
      # only be executed if no :content is set
      @content_default = true
      @resource.no_content
    end

    validate do |val|
      fail "read-only attribute" if !@content_default
    end

    def insync?(is)
      result = super

      if ! result
        string_file_diff(@resource[:path], @resource.should_content)
      end

      result
    end

    def is_to_s(value)
      md5(value)
    end

    def should_to_s(value)
      md5(value)
    end
  end

  newparam(:use_tag, :boolean => true, :parent => Puppet::Parameter::Boolean) do
    desc "Should the +tag+ attribute be used to collect file_fragments beside the +path+ attribute? (all specified tags must exists on the file_fragment's)"

    defaultto true
  end

  def no_content
    "\0PLEASE_MANAGE_THIS_WITH_FILE_CONCAT\0"
  end

  def should_content
    return @generated_content if @generated_content
    @generated_content = ""
    content_fragments = []

    catalog.resources.select do |r|
      r.is_a?(Puppet::Type.type(:file_fragment)) && (
        r[:path] == value(:path) ||
        use_tag? && value(:tag) && value(:tag).all? { |o| r[:tag] && r[:tag].include?(o) }
      )
    end.each do |r|

      if r[:content].nil? == false
        fragment_content = r[:content]
      elsif r[:source].nil? == false
        tmp = Puppet::FileServing::Content.indirection.find(r[:source], :environment => catalog.environment)
        fragment_content = tmp.content
      end

      content_fragments << [
        "#{r[:order]}_#{r[:name]}", # sort key as in old concat module
        fragment_content
      ]

    end

    content_fragments.sort { |l,r| l[0] <=> r[0] }.each do |cf|
      @generated_content += cf[1]
    end

    @generated_content
  end

  def stat(dummy_arg = nil)
    return @stat if @stat and not @stat == :needs_stat
    @stat = begin
      ::File.stat(value(:path))
    rescue Errno::ENOENT => error
      nil
    rescue Errno::EACCES => error
      warning "Could not stat; permission denied"
      nil
    end
  end

  ### took from original type/file
  # There are some cases where all of the work does not get done on
  # file creation/modification, so we have to do some extra checking.
  def property_fix
    properties.each do |thing|
      next unless [:mode, :owner, :group].include?(thing.name)

      # Make sure we get a new stat object
      @stat = :needs_stat
      currentvalue = thing.retrieve
      thing.sync unless thing.safe_insync?(currentvalue)
    end
  end
end

#!/usr/bin/env ruby
require 'fileutils'

class Mirror
  SPECS_FILES = [
    "specs.#{Gem.marshal_version}",
    "prerelease_specs.#{Gem.marshal_version}",
    "latest_specs.#{Gem.marshal_version}",
  ]

  DEFAULT_URI = 'http://production.cf.rubygems.org/'
  RUBY = 'ruby'

  # External commands
  NIX_PREFETCH_URL = 'nix-prefetch-url'
  CURL = 'curl'

  def initialize(to_dir, retries: 5)
    @from = DEFAULT_URI
    @to = to_dir
  end

  def update
    # TODO: use the latest enpoint and fallback on the full sync
    # TODO: only sync if the spec files have changed or the sync is not full
    puts 'Fetching specs'
    update_specs
    gems = load_gems_from_specs
    gems.each.with_index do |gem, i|
      printf '[% 6d/% 6d] %-40s: ', i, gems.size, gemname(gem)
      file = gemhash(gem)
      if File.exists?(file)
        puts 'Existing'
        next
      end
      url = gemurl(gem)

      sha256 = get_gem_hash(url)
      if sha256.empty?
        puts 'Missing sha256'
      else
        FileUtils.mkdir_p(File.dirname(file))
        begin
          File.write(file, sha256)
        rescue Object
          # make sure the file is not created empty or half-written
          File.unlink(file) rescue nil
        end
        puts 'Added'
      end
    end
  end

  private

  def get_gem_hash(url)
    `#{NIX_PREFETCH_URL} --type sha256 "#{url}" 2>/dev/null`.strip
  end

  def update_specs
    SPECS_FILES.each do |sf|
      sfz = "#{sf}.gz"

      specz = work(sfz)
      fetch(from(sfz), specz)
      #@fetcher.fetch(from(sfz), specz)
      open(work(sf), 'wb') { |f| f << Gem.gunzip(File.read(specz)) }
    end
  end

  def from(*args)
    File.join(@from, *args)
  end

  def to(*args)
    File.join(@to, *args)
  end

  def fetch(from, to)
    FileUtils.mkdir_p(File.dirname(to))
    if !system(CURL, '--fail', '--show-error', '--location', '--retry', '5', '--output', to, from)
      raise "Unable to fetch #{from(sfz)}"
    end
  end

  def work(*args)
    to('mirror', *args)
  end

  def load_gems_from_specs
    gems = []

    SPECS_FILES.each do |sf|
      gems += Marshal.load(File.read(work(sf)))
    end

    gems
  end

  def gemhash(gem)
    name, ver, plat = *gem
    file = "#{ver}#{"-#{plat}" unless plat == RUBY}.sha256"
    to('gems', name[0,2], name, file)
  end

  def gemname(gem)
    name, ver, plat = *gem
    # If the platform is ruby, it is not in the gem name
    "#{name}-#{ver}#{"-#{plat}" unless plat == RUBY}"
  end

  def gemurl(gem)
    from('gems', gemname(gem) + '.gem')
  end
end

if __FILE__ == $0
  top = File.expand_path(__dir__)

  m = Mirror.new(top)
  m.update
end

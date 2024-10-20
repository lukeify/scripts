#!/usr/bin/env ruby

require "find"
require "openssl"

$duplicates_increment = 0
$files_increment = 0

def log_duplicate_progress(is_duplicate:)
  $duplicates_increment += 1 if is_duplicate

  print "\r#{$duplicates_increment} duplicates / #{$files_increment} files scanned"
  $files_increment += 1
end

def find_dupes(target)
  duplicates = {}

  Find.find(target) do |path|
    Find.prune if File.basename(path).start_with?(".")

    if FileTest.file?(path)
      dgst = OpenSSL::Digest::SHA256.file(path).hexdigest

      log_duplicate_progress(is_duplicate: duplicates.key?(dgst))

      duplicates[dgst] = [] unless duplicates.key?(dgst)
      duplicates[dgst] << path
    end
  end

  puts "\n==="
  duplicates.select { |k, v| v.size > 1 }.each do |k, v|
    puts "duplicate: #{k}"
    puts v
  end
end

def find_unqiues(source, target)

end

case ARGV[0]
when "duplicates"
  find_dupes(ARGV[1])
when "uniques"
  find_uniques(ARGV[1], ARGV[2])
else
  STDERR.puts "Please provide either 'duplicates' or 'uniques' to 'sharpener'."
  exit(1)
end
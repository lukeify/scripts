#!/usr/bin/env ruby

require "find"
require "openssl"

$duplicates_increment = 0
$files_increment = 0

##
# Logs progress finding duplicates to stdout.
#
# @param is_duplicate A boolean indicating if the progress to be logged includes a duplicate file or not.
def log_duplicate_progress(is_duplicate:)
  $duplicates_increment += 1 if is_duplicate

  print "\r#{$duplicates_increment} duplicates / #{$files_increment} files scanned"
  $files_increment += 1
end

##
# Finds all duplicates—recursively—within the supplied target directory. Ignores any directories or files that are
# prefixed with a period character.
#
# @param target The string that represents the path to the target directory.
#
def find_dupes(target)
  duplicates = {}

  Find.find(target) do |path|
    Find.prune if File.basename(path).start_with?(".")

    if FileTest.file?(path)
      digest = OpenSSL::Digest::SHA256.file(path).hexdigest

      log_duplicate_progress(is_duplicate: duplicates.key?(digest))

      duplicates[digest] = [] unless duplicates.key?(digest)
      duplicates[digest] << path
    end
  end

  STDOUT.puts "\n==="
  duplicates.select { |k, v| v.size > 1 }.each do |k, v|
    STDOUT.puts "duplicate: #{k}"
    STDOUT.puts "#{v}"
  end
end

##
# Given a source directory, find all files in source directory that are not present in the target directory. Ignores any
# directories or files that are prefixed with a period character.
#
# @param source
# @param target
#
def find_unqiues(source, target); end

case ARGV[0]
when "duplicates"
  find_dupes(ARGV[1])
when "uniques"
  find_uniques(ARGV[1], ARGV[2])
else
  STDERR.puts "Please provide either 'duplicates' or 'uniques' to 'sharpener'."
  exit(1)
end
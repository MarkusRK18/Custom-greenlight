#!/usr/bin/env ruby
# Managed by SIETConnect assets: prepare speaker metadata before ready callbacks.
require 'optparse'
options = {}
OptionParser.new do |parser|
  parser.on('-m', '--meeting_id ID') { |value| options[:meeting] = value }
  parser.on('-f', '--format FORMAT') { |value| options[:format] = value }
end.parse!
exit 0 unless %w[presentation video].include?(options[:format])
abort 'Missing recording id.' unless options[:meeting] && !options[:meeting].empty?
success = system('/usr/bin/python3', '/usr/local/libexec/sietconnect-publish-speakers.py',
                 '--meeting-id', options[:meeting], '--format', options[:format])
abort 'SIETConnect speaker timeline publication failed.' unless success

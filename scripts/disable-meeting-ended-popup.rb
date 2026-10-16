#!/usr/bin/env ruby
# Use BBB's native redirect setting rather than hiding the ended-session dialog.
require 'yaml'
require 'fileutils'
require 'tmpdir'

abort 'Run with sudo on the meeting server.' unless Process.uid.zero?
path = '/etc/bigbluebutton/bbb-html5.yml'
before = File.exist?(path) ? File.binread(path) : nil
settings = YAML.safe_load(before || '', permitted_classes: [Symbol], aliases: true) || {}
abort 'Expected a mapping in bbb-html5.yml.' unless settings.is_a?(Hash)
settings['public'] ||= {}
abort 'Expected public settings to be a mapping.' unless settings['public'].is_a?(Hash)
settings['public']['app'] ||= {}
app = settings['public']['app']
abort 'Expected public.app settings to be a mapping.' unless app.is_a?(Hash)
if app['skipMeetingEnded'] == true
  puts 'Meeting-ended popup is already disabled.'
  exit
end
app['skipMeetingEnded'] = true
backup = Dir.mktmpdir('sietconnect-meeting-ended.', '/var/backups')
FileUtils.cp(path, File.join(backup, 'bbb-html5.yml')) if before
begin
  File.write(path, YAML.dump(settings))
  File.chmod(0o644, path) unless before
  # BBB web loads the client settings used by newly joining clients.
  raise 'Unable to restart bbb-web.' unless system('systemctl', 'restart', 'bbb-web')
rescue StandardError
  before ? File.binwrite(path, before) : FileUtils.rm_f(path)
  system('systemctl', 'restart', 'bbb-web')
  raise
end
puts "Meeting-ended popup disabled; users return to the room invitation. Backup: #{backup}"

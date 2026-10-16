#!/usr/bin/env ruby
# Use BBB's native redirect setting rather than hiding the ended-session dialog.
require 'yaml'
require 'fileutils'
require 'tmpdir'

abort 'Run with sudo on the meeting server.' unless Process.uid.zero?
path = '/etc/bigbluebutton/bbb-html5.yml'
before = File.exist?(path) ? File.binread(path) : nil
recovered = false
begin
  settings = YAML.safe_load(before || '', permitted_classes: [Symbol], aliases: true) || {}
rescue Psych::SyntaxError => error
  original_path = path + '.before-sietconnect'
  abort "Invalid YAML in #{path} at line #{error.line}. No changes made; repair the YAML before retrying." unless File.file?(original_path)
  original = File.binread(original_path)
  # Recover only when the old branding substitutions exactly explain the damage.
  damaged = original.gsub(/^(\s*clientTitle:\s*).+$/, '\\1SIETConnect')
  { 'skipMeetingEnded' => 'true', 'displayBbbServerVersion' => 'false',
    'showHelpButton' => 'false', 'copyright' => "'Sri Shakthi'" }.each do |key, value|
    damaged = damaged.gsub(/^(\s*#{key}:\s*).+$/) { Regexp.last_match(1) + value }
  end
  abort "Invalid YAML in #{path} at line #{error.line}. Backup does not explain the damage; no changes made. Repair the YAML before retrying." unless damaged == before
  begin
    settings = YAML.safe_load(original, permitted_classes: [Symbol], aliases: true) || {}
  rescue Psych::Exception
    abort "The saved backup #{original_path} is also invalid. No changes made."
  end
  recovered = true
end
abort 'Expected a mapping in bbb-html5.yml.' unless settings.is_a?(Hash)
settings['public'] ||= {}
abort 'Expected public settings to be a mapping.' unless settings['public'].is_a?(Hash)
settings['public']['app'] ||= {}
app = settings['public']['app']
abort 'Expected public.app settings to be a mapping.' unless app.is_a?(Hash)
if app['skipMeetingEnded'] == true && !recovered
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

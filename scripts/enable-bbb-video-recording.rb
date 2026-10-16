#!/usr/bin/env ruby
# frozen_string_literal: true

# Add BBB's installed combined-video workflow without replacing existing formats.
require 'fileutils'
require 'yaml'
require 'time'

def read_config(path)
  YAML.safe_load(File.read(path), permitted_classes: [Symbol], aliases: true)
end

mode = ARGV.fetch(0, '--check')
abort 'Usage: enable-bbb-video-recording.rb --check|--apply|--apply-no-restart' unless %w[--check --apply --apply-no-restart].include?(mode)
abort 'Run as root on the BBB server.' unless Process.uid.zero?

base = '/usr/local/bigbluebutton/core/scripts'
%w[process/video.rb publish/video.rb video.yml].each do |file|
  abort "BBB video recording component is missing: #{file}. Install bbb-playback-video for this BBB release, then rerun." unless File.file?(File.join(base, file))
end
video_config = read_config(File.join(base, 'video.yml'))
playback_dir = video_config.fetch('playback_dir')
abort 'BBB video playback assets are missing. Install bbb-playback-video on this BBB server.' unless File.file?(File.join(playback_dir, 'index.html.erb'))

base_config = read_config(File.join(base, 'bigbluebutton.yml'))
override_path = '/etc/bigbluebutton/recording/recording.yml'
override = File.file?(override_path) ? read_config(override_path) : {}
abort 'Invalid BBB recording override.' unless override.is_a?(Hash) && base_config.is_a?(Hash)
steps = (override['steps'] || base_config['steps']).dup
abort 'BBB recording workflow has no captions step.' unless steps.key?('captions')

next_steps = Array(steps['captions'])
next_steps << 'process:video' unless next_steps.include?('process:video')
steps['captions'] = next_steps
if steps.key?('process:video') && steps['process:video'] != 'publish:video'
  abort 'Existing video workflow differs; inspect it before changing the recording steps.'
end
steps['process:video'] = 'publish:video'
override['steps'] = steps

if mode == '--check'
  puts 'BBB combined-video workflow is available.'
  exit
end

FileUtils.mkdir_p(File.dirname(override_path))
new_config = YAML.dump(override)
if File.file?(override_path) && File.read(override_path) == new_config
  puts 'BBB combined-video workflow is already enabled.'
  exit
end
backup_dir = "/var/backups/sietconnect-video-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}"
FileUtils.mkdir_p(backup_dir, mode: 0o700)
FileUtils.cp(override_path, File.join(backup_dir, 'recording.yml.before')) if File.file?(override_path)
old_config = File.file?(override_path) ? File.binread(override_path) : nil
begin
  File.write(override_path, new_config)
  File.chmod(0o644, override_path)
  effective_steps = base_config.merge(read_config(override_path)).fetch('steps')
  abort 'BBB video workflow was not saved.' unless Array(effective_steps['captions']).include?('process:video') &&
                                                   effective_steps['process:video'] == 'publish:video'
  if mode == '--apply'
    abort 'Could not restart BBB recording workers.' unless system('systemctl', 'restart', 'bbb-rap-starter.service', 'bbb-rap-resque-worker.service')
  end
rescue StandardError, SystemExit
  old_config ? File.binwrite(override_path, old_config) : File.delete(override_path)
  raise
end
puts "BBB combined-video workflow enabled. Backup: #{backup_dir}"

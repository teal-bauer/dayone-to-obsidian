#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'fileutils'
require 'time'
require 'zip'
require 'set'

class DayOneToObsidian
  WEATHER_CODES = {
    'clear' => 'Clear',
    'clear-day' => 'Clear',
    'clear-night' => 'Clear Night',
    'cloudy' => 'Cloudy',
    'cloudy-night' => 'Cloudy Night',
    'partly-cloudy' => 'Partly Cloudy',
    'partly-cloudy-day' => 'Partly Cloudy',
    'partly-cloudy-night' => 'Partly Cloudy Night',
    'rain' => 'Rain',
    'snow' => 'Snow',
    'sleet' => 'Sleet',
    'wind' => 'Windy',
    'fog' => 'Fog',
    'hail' => 'Hail',
    'thunderstorm' => 'Thunderstorm'
  }.freeze

  MOON_PHASES = {
    'new' => 'New Moon',
    'waxing-crescent' => 'Waxing Crescent',
    'first-quarter' => 'First Quarter',
    'waxing-gibbous' => 'Waxing Gibbous',
    'full' => 'Full Moon',
    'waning-gibbous' => 'Waning Gibbous',
    'last-quarter' => 'Last Quarter',
    'waning-crescent' => 'Waning Crescent'
  }.freeze

  def initialize(input_path, output_dir)
    @input_path = input_path
    @output_dir = output_dir
    @entries_dir = File.join(output_dir, 'entries')
    @attachments_dir = File.join(output_dir, 'attachments')
    @photo_map = {} # identifier -> md5 mapping
    @used_filenames = Set.new
  end

  def convert
    FileUtils.mkdir_p(@entries_dir)
    FileUtils.mkdir_p(@attachments_dir)

    if @input_path.end_with?('.zip')
      convert_from_zip
    else
      convert_from_directory
    end
  end

  private

  def convert_from_zip
    Zip::File.open(@input_path) do |zip_file|
      # Find and parse the journal JSON
      journal_entry = zip_file.glob('*.json').first || zip_file.glob('**/*.json').first
      raise "No JSON file found in ZIP" unless journal_entry

      journal_data = JSON.parse(journal_entry.get_input_stream.read)
      entries = journal_data['entries'] || []

      # Extract photos
      zip_file.glob('**/photos/*').each do |photo_entry|
        filename = File.basename(photo_entry.name)
        dest_path = File.join(@attachments_dir, filename)
        zip_file.extract(photo_entry, dest_path) unless File.exist?(dest_path)
      end

      convert_entries(entries)
    end
  end

  def convert_from_directory
    json_files = Dir.glob(File.join(@input_path, '*.json')) +
                 Dir.glob(File.join(@input_path, '**/*.json'))

    json_files.each do |json_file|
      journal_data = JSON.parse(File.read(json_file))
      entries = journal_data['entries'] || []

      # Copy photos
      photos_dir = File.join(File.dirname(json_file), 'photos')
      if Dir.exist?(photos_dir)
        Dir.glob(File.join(photos_dir, '*')).each do |photo|
          FileUtils.cp(photo, @attachments_dir) unless File.exist?(File.join(@attachments_dir, File.basename(photo)))
        end
      end

      convert_entries(entries)
    end
  end

  def convert_entries(entries)
    entries.each do |entry|
      convert_entry(entry)
    end
    puts "Converted #{entries.length} entries"
  end

  def convert_entry(entry)
    # Build photo identifier to md5 map
    build_photo_map(entry)

    # Generate frontmatter
    frontmatter = build_frontmatter(entry)

    # Convert content
    content = convert_content(entry)

    # Generate filename
    filename = generate_filename(entry)

    # Write file
    output_path = File.join(@entries_dir, filename)
    File.write(output_path, "#{frontmatter}#{content}")
  end

  def build_photo_map(entry)
    return unless entry['photos']

    entry['photos'].each do |photo|
      @photo_map[photo['identifier']] = photo['md5']
    end
  end

  def build_frontmatter(entry)
    fm = {}

    # Core metadata
    fm['uuid'] = entry['uuid'] if entry['uuid']
    fm['created'] = entry['creationDate'] if entry['creationDate']
    fm['modified'] = entry['modifiedDate'] if entry['modifiedDate']
    fm['timezone'] = entry['timeZone'] if entry['timeZone']

    # Status flags
    fm['starred'] = entry['starred'] if entry['starred']
    fm['pinned'] = entry['isPinned'] if entry['isPinned']
    fm['all_day'] = entry['isAllDay'] if entry['isAllDay']

    # Tags (Obsidian format)
    if entry['tags'] && !entry['tags'].empty?
      fm['tags'] = entry['tags'].map { |t| sanitize_tag(t) }
    end

    # Location
    if entry['location']
      loc = entry['location']
      fm['location'] = {
        'name' => loc['placeName'],
        'locality' => loc['localityName'],
        'region' => loc['administrativeArea'],
        'country' => loc['country'],
        'latitude' => loc['latitude'],
        'longitude' => loc['longitude']
      }.compact
    end

    # Weather
    if entry['weather']
      w = entry['weather']
      weather = {}
      weather['conditions'] = w['conditionsDescription'] if w['conditionsDescription']
      weather['temperature_c'] = w['temperatureCelsius'] if w['temperatureCelsius']
      weather['humidity'] = w['relativeHumidity'] if w['relativeHumidity'] && w['relativeHumidity'] > 0
      weather['pressure_mb'] = w['pressureMB'] if w['pressureMB']
      weather['wind_speed_kph'] = w['windSpeedKPH'] if w['windSpeedKPH']
      weather['wind_bearing'] = w['windBearing'] if w['windBearing']
      weather['visibility_km'] = w['visibilityKM'] if w['visibilityKM'] && w['visibilityKM'] > 0
      weather['moon_phase'] = MOON_PHASES[w['moonPhaseCode']] if w['moonPhaseCode']
      fm['weather'] = weather unless weather.empty?
    end

    # Activity
    if entry['userActivity']
      activity = entry['userActivity']
      fm['activity'] = {
        'type' => activity['activityName'],
        'steps' => activity['stepCount']
      }.compact
    end

    # Device info
    if entry['creationDevice'] || entry['creationDeviceType']
      fm['device'] = {
        'name' => entry['creationDevice'],
        'type' => entry['creationDeviceType'],
        'model' => entry['creationDeviceModel'],
        'os' => entry['creationOSName'],
        'os_version' => entry['creationOSVersion']
      }.compact
    end

    # Photo metadata
    if entry['photos'] && !entry['photos'].empty?
      fm['photos'] = entry['photos'].map do |photo|
        photo_meta = {
          'file' => "#{photo['md5']}.#{photo['type'] || 'jpeg'}",
          'identifier' => photo['identifier']
        }
        photo_meta['camera'] = "#{photo['cameraMake']} #{photo['cameraModel']}".strip if photo['cameraMake'] || photo['cameraModel']
        photo_meta['lens'] = photo['lensModel'] if photo['lensModel']
        photo_meta['date'] = photo['date'] if photo['date']
        photo_meta['dimensions'] = "#{photo['width']}x#{photo['height']}" if photo['width'] && photo['height']
        photo_meta
      end
    end

    # Editing time
    fm['editing_time_seconds'] = entry['editingTime'].round if entry['editingTime'] && entry['editingTime'] > 0

    yaml_content = fm.to_yaml.sub(/^---\n/, '')
    "---\n#{yaml_content}---\n\n"
  end

  def convert_content(entry)
    text = entry['text'] || ''

    # Remove escaped backslashes from Day One's markdown
    text = unescape_dayone_markdown(text)

    # Convert Day One image references to Obsidian format
    text = convert_image_references(text)

    # Clean up any zero-width spaces that Day One inserts
    text = text.gsub(/\u200B/, '')

    text
  end

  def unescape_dayone_markdown(text)
    # Day One escapes periods, hyphens, parentheses, etc.
    # We need to unescape them for standard markdown
    text
      .gsub(/\\\./, '.')
      .gsub(/\\-/, '-')
      .gsub(/\\\(/, '(')
      .gsub(/\\\)/, ')')
      .gsub(/\\\[/, '[')
      .gsub(/\\\]/, ']')
      .gsub(/\\#/, '#')
      .gsub(/\\>/, '>')
      .gsub(/\\_/, '_')
      .gsub(/\\\*/, '*')
      .gsub(/\\`/, '`')
      .gsub(/\\~/, '~')
      .gsub(/\\!/, '!')
  end

  def convert_image_references(text)
    # Convert dayone-moment://IDENTIFIER to Obsidian ![[filename]]
    text.gsub(/!\[\]\(dayone-moment:\/\/([A-F0-9]+)\)/) do |_match|
      identifier = Regexp.last_match(1)
      md5 = @photo_map[identifier]
      if md5
        "![[#{md5}.jpeg]]"
      else
        # Keep original if we can't find the mapping
        "<!-- Missing photo: #{identifier} -->"
      end
    end
  end

  def generate_filename(entry)
    date = Time.parse(entry['creationDate'])
    date_str = date.strftime('%Y-%m-%d')

    # Try to extract title from first heading or first line
    title = extract_title(entry['text'])

    base_filename = if title && !title.empty?
      # Sanitize title for filename
      safe_title = title
        .gsub(/[\/\\:*?"<>|]/, '-')
        .gsub(/\s+/, ' ')
        .strip
        .slice(0, 50)
      "#{date_str} #{safe_title}"
    else
      # Use UUID if no title
      "#{date_str} #{entry['uuid'][0..7]}"
    end

    # Handle duplicate filenames by appending UUID fragment
    filename = "#{base_filename}.md"
    if @used_filenames.include?(filename)
      filename = "#{base_filename} (#{entry['uuid'][0..7]}).md"
    end

    @used_filenames.add(filename)
    filename
  end

  def extract_title(text)
    return nil unless text

    # Look for first heading
    if text =~ /^#\s+(.+?)(?:\n|\\n|$)/
      return unescape_dayone_markdown(Regexp.last_match(1)).strip
    end

    # Otherwise use first non-empty line
    first_line = text.lines.find { |l| l.strip.length > 0 }
    return nil unless first_line

    # Remove image references and clean up
    title = first_line
      .gsub(/!\[\]\(dayone-moment:\/\/[^)]+\)/, '')
      .gsub(/^#+\s*/, '')
      .strip

    title.empty? ? nil : unescape_dayone_markdown(title).slice(0, 50)
  end

  def sanitize_tag(tag)
    # Convert tag to Obsidian-friendly format
    tag
      .gsub(/\s+/, '-')
      .gsub(/[^\w\-]/, '')
      .downcase
  end
end

# CLI interface
if __FILE__ == $0
  if ARGV.length < 2
    puts "Usage: #{$0} <input_path> <output_dir>"
    puts ""
    puts "  input_path: Path to Day One export ZIP file or extracted directory"
    puts "  output_dir: Directory where Obsidian vault will be created"
    exit 1
  end

  input_path = ARGV[0]
  output_dir = ARGV[1]

  converter = DayOneToObsidian.new(input_path, output_dir)
  converter.convert

  puts "Conversion complete! Output written to: #{output_dir}"
end

# Day One to Obsidian Converter

Convert Day One journal exports to Obsidian-compatible Markdown files with full metadata preservation.

## Browser Version

Looking for a client-side version that runs entirely in your browser?

- **[Try it online](https://teal-bauer.github.io/dayone-to-obsidian-js/)** - No installation required
- **[JavaScript version repo](https://github.com/teal-bauer/dayone-to-obsidian-js)** - Pure JS implementation

This Ruby version offers a command-line tool and self-hosted web interface.

## Features

- Reads Day One ZIP exports directly (or extracted directories)
- Supports **all attachment types**: photos, videos, audio, and PDFs
- Preserves all metadata in YAML frontmatter:
  - UUID, creation/modification dates, timezone
  - Tags (converted to Obsidian-friendly format)
  - Location (place name, city, region, country, coordinates)
  - Weather (conditions, temperature, humidity, wind, moon phase)
  - Activity (type, step count)
  - Device info (name, type, model, OS)
  - Photo metadata (camera, lens, date, dimensions)
  - Starred/pinned flags, editing time
- Converts `dayone-moment://` image references to Obsidian `![[filename]]` embeds
- Unescapes Day One's markdown escaping
- Handles duplicate filenames by appending UUID fragment
- Copies photos to attachments folder

## Requirements

- Ruby 2.7+
- Bundler (`gem install bundler`)

## Installation

```bash
bundle install
```

## Usage

### Web Interface (Recommended)

1. Start the server:
```bash
bundle exec ruby app.rb
```

2. Open http://localhost:4567 in your browser

3. Drag and drop your Day One export ZIP file

4. Download the converted Obsidian vault

### Command Line

```bash
ruby dayone_to_obsidian.rb <input_path> <output_dir>
```

**Arguments:**
- `input_path`: Path to Day One export ZIP file or extracted directory
- `output_dir`: Directory where Obsidian vault will be created

**Example:**
```bash
ruby dayone_to_obsidian.rb ~/Downloads/Journal.zip ~/Documents/ObsidianVault/DayOne
```

## Output Structure

```
output_dir/
├── entries/
│   ├── 2024-01-15 My Journal Entry.md
│   ├── 2024-01-16 Another Entry.md
│   └── ...
└── attachments/
    ├── abc123def456.jpeg
    └── ...
```

## Frontmatter Example

```yaml
---
uuid: 5E2B69750D5248378592CC8DAE174009
created: '2024-01-15T22:06:56Z'
modified: '2024-01-16T17:00:26Z'
timezone: America/Denver
starred: true
tags:
- travel
- food
location:
  name: Central Park
  locality: New York
  region: NY
  country: United States
  latitude: 40.782421
  longitude: -73.965606
weather:
  conditions: Clear
  temperature_c: 22
  humidity: 45
  moon_phase: Full Moon
activity:
  type: Walking
  steps: 8234
device:
  name: iPhone 15 Pro
  type: iPhone
  os: iOS
  os_version: '17.2'
photos:
- file: abc123def456.jpeg
  camera: Apple iPhone 15 Pro
  lens: iPhone 15 Pro back camera
  dimensions: 4032x3024
---
```

## License

MIT

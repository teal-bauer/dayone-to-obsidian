#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sinatra'
require 'fileutils'
require 'tmpdir'
require_relative 'dayone_to_obsidian'

set :port, 4567
set :bind, '0.0.0.0'

# Cleanup old temp files on startup
Dir.glob(File.join(Dir.tmpdir, 'dayone_*')).each do |dir|
  FileUtils.rm_rf(dir) if File.mtime(dir) < Time.now - 3600
end

get '/' do
  erb :index
end

post '/convert' do
  unless params[:file] && params[:file][:tempfile]
    halt 400, erb(:error, locals: { message: 'No file uploaded' })
  end

  # Create temp directories
  temp_id = "dayone_#{Time.now.to_i}_#{rand(10000)}"
  temp_dir = File.join(Dir.tmpdir, temp_id)
  input_path = File.join(temp_dir, 'input.zip')
  output_dir = File.join(temp_dir, 'output')

  begin
    FileUtils.mkdir_p(temp_dir)

    # Save uploaded file
    File.open(input_path, 'wb') do |f|
      f.write(params[:file][:tempfile].read)
    end

    # Convert
    converter = DayOneToObsidian.new(input_path, output_dir)
    converter.convert

    # Create output ZIP
    output_zip = File.join(temp_dir, 'converted.zip')
    system("cd #{output_dir} && zip -r #{output_zip} .")

    # Send file
    send_file output_zip,
              filename: 'dayone-obsidian-export.zip',
              type: 'application/zip',
              disposition: 'attachment'

  rescue StandardError => e
    halt 500, erb(:error, locals: { message: "Conversion failed: #{e.message}" })
  ensure
    # Cleanup in background after 10 seconds
    Thread.new do
      sleep 10
      FileUtils.rm_rf(temp_dir) if File.exist?(temp_dir)
    end
  end
end

__END__

@@layout
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Day One to Obsidian Converter</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }

    .container {
      background: white;
      border-radius: 16px;
      box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
      max-width: 600px;
      width: 100%;
      padding: 40px;
    }

    h1 {
      font-size: 32px;
      margin-bottom: 10px;
      color: #1a202c;
    }

    .subtitle {
      color: #718096;
      margin-bottom: 30px;
      font-size: 16px;
    }

    .upload-area {
      border: 3px dashed #cbd5e0;
      border-radius: 12px;
      padding: 60px 20px;
      text-align: center;
      transition: all 0.3s;
      cursor: pointer;
      background: #f7fafc;
    }

    .upload-area:hover {
      border-color: #667eea;
      background: #edf2f7;
    }

    .upload-area.dragover {
      border-color: #667eea;
      background: #e6fffa;
    }

    .upload-icon {
      font-size: 48px;
      margin-bottom: 20px;
    }

    .upload-text {
      font-size: 18px;
      color: #2d3748;
      margin-bottom: 10px;
    }

    .upload-hint {
      font-size: 14px;
      color: #718096;
    }

    input[type="file"] {
      display: none;
    }

    button {
      width: 100%;
      padding: 16px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 16px;
      font-weight: 600;
      cursor: pointer;
      margin-top: 20px;
      transition: transform 0.2s, opacity 0.2s;
    }

    button:hover {
      transform: translateY(-2px);
      opacity: 0.9;
    }

    button:active {
      transform: translateY(0);
    }

    button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
      transform: none;
    }

    .spinner {
      display: inline-block;
      width: 16px;
      height: 16px;
      border: 2px solid rgba(255, 255, 255, 0.3);
      border-radius: 50%;
      border-top-color: white;
      animation: spin 0.8s linear infinite;
      margin-right: 8px;
    }

    @keyframes spin {
      to { transform: rotate(360deg); }
    }

    .selected-file {
      margin-top: 20px;
      padding: 16px;
      background: #edf2f7;
      border-radius: 8px;
      color: #2d3748;
      font-size: 14px;
    }

    .error {
      background: #fed7d7;
      color: #c53030;
      padding: 16px;
      border-radius: 8px;
      margin-bottom: 20px;
    }

    .features {
      margin-top: 30px;
      padding-top: 30px;
      border-top: 1px solid #e2e8f0;
    }

    .features h3 {
      font-size: 16px;
      color: #2d3748;
      margin-bottom: 15px;
    }

    .features ul {
      list-style: none;
      font-size: 14px;
      color: #718096;
    }

    .features li {
      padding: 6px 0;
      padding-left: 24px;
      position: relative;
    }

    .features li:before {
      content: "✓";
      position: absolute;
      left: 0;
      color: #48bb78;
      font-weight: bold;
    }
  </style>
</head>
<body>
  <%= yield %>
</body>
</html>

@@index
<div class="container">
  <h1>Day One → Obsidian</h1>
  <p class="subtitle">Convert your Day One journal exports to Obsidian-compatible Markdown</p>

  <form action="/convert" method="post" enctype="multipart/form-data" id="uploadForm">
    <div class="upload-area" id="uploadArea">
      <div class="upload-icon">📦</div>
      <div class="upload-text">Drop your Day One export here</div>
      <div class="upload-hint">or click to browse</div>
      <input type="file" name="file" id="fileInput" accept=".zip" required>
    </div>

    <div id="selectedFile" class="selected-file" style="display: none;">
      <strong>Selected:</strong> <span id="fileName"></span>
    </div>

    <button type="submit" id="submitBtn">
      Convert to Obsidian
    </button>
  </form>

  <div class="features">
    <h3>What gets preserved:</h3>
    <ul>
      <li>All text content and formatting</li>
      <li>Photos and attachments</li>
      <li>Location, weather, and activity data</li>
      <li>Tags, starred entries, and metadata</li>
      <li>Creation and modification dates</li>
    </ul>
  </div>
</div>

<script>
  const uploadArea = document.getElementById('uploadArea');
  const fileInput = document.getElementById('fileInput');
  const selectedFile = document.getElementById('selectedFile');
  const fileName = document.getElementById('fileName');
  const submitBtn = document.getElementById('submitBtn');
  const uploadForm = document.getElementById('uploadForm');

  // Click to upload
  uploadArea.addEventListener('click', () => fileInput.click());

  // Drag and drop
  uploadArea.addEventListener('dragover', (e) => {
    e.preventDefault();
    uploadArea.classList.add('dragover');
  });

  uploadArea.addEventListener('dragleave', () => {
    uploadArea.classList.remove('dragover');
  });

  uploadArea.addEventListener('drop', (e) => {
    e.preventDefault();
    uploadArea.classList.remove('dragover');

    if (e.dataTransfer.files.length > 0) {
      fileInput.files = e.dataTransfer.files;
      showSelectedFile(e.dataTransfer.files[0]);
    }
  });

  // File selected
  fileInput.addEventListener('change', (e) => {
    if (e.target.files.length > 0) {
      showSelectedFile(e.target.files[0]);
    }
  });

  function showSelectedFile(file) {
    fileName.textContent = file.name;
    selectedFile.style.display = 'block';
  }

  // Form submission
  uploadForm.addEventListener('submit', () => {
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<span class="spinner"></span> Converting...';
  });
</script>

@@error
<div class="container">
  <h1>⚠️ Error</h1>
  <p class="subtitle">Something went wrong</p>

  <div class="error">
    <%= message %>
  </div>

  <button onclick="window.location.href='/'">
    Try Again
  </button>
</div>

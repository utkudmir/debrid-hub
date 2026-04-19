#!/usr/bin/env ruby
require "json"
require "yaml"

ROOT_DIR = File.expand_path("..", __dir__)
DEVICE_POOL_FILE = File.join(ROOT_DIR, "ci", "device-pool.yml")

verify_profile = ARGV[0].to_s
platform = ARGV[1].to_s
host_arch = ENV.fetch("ANDROID_MATRIX_HOST_ARCH", "x86_64")

abort("usage: #{$PROGRAM_NAME} <profile> <android|ios>") if verify_profile.empty? || platform.empty?
abort("device pool file not found: #{DEVICE_POOL_FILE}") unless File.file?(DEVICE_POOL_FILE)

def normalize_entries(entries)
  Array(entries).each_with_object([]) do |entry, normalized_entries|
    next unless entry.is_a?(Hash)

    normalized = {}
    entry.each { |key, value| normalized[key.to_s] = value }
    normalized_entries << normalized
  end
end

def merge_entries(base_entries, override_entries)
  merged = base_entries.map(&:dup)
  label_index = {}

  merged.each_with_index do |entry, idx|
    label = entry["label"]&.to_s
    next if label.nil? || label.empty?

    label_index[label] = idx
  end

  normalize_entries(override_entries).each do |entry|
    label = entry["label"]&.to_s
    if label && !label.empty? && label_index.key?(label)
      merged[label_index[label]] = entry
    else
      merged << entry
      label_index[label] = merged.length - 1 if label && !label.empty?
    end
  end

  merged
end

def resolve_profile(name, profiles, stack = [])
  raise "profile_not_found:#{name}" unless profiles.key?(name)
  raise "profile_cycle:#{(stack + [name]).join("->")}" if stack.include?(name)

  profile = profiles[name] || {}
  resolved = {
    "android" => [],
    "ios" => []
  }

  Array(profile["includes"]).each do |included_name|
    included = resolve_profile(included_name, profiles, stack + [name])
    resolved["android"] = merge_entries(resolved["android"], included["android"])
    resolved["ios"] = merge_entries(resolved["ios"], included["ios"])
  end

  resolved["android"] = merge_entries(resolved["android"], profile["android"])
  resolved["ios"] = merge_entries(resolved["ios"], profile["ios"])
  resolved
end

def slugify(value)
  slug = value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_+|_+$/, "")
  slug.empty? ? "default" : slug
end

def android_arch_for_host(_requested_arch, host_arch)
  host = host_arch.to_s.downcase
  return "arm64-v8a" if host == "arm64-v8a" || host == "arm64" || host == "aarch64"

  "x86_64"
end

def android_ci_device_profile(requested_profile)
  profile = requested_profile.to_s
  return "pixel" if profile.empty?

  # Keep CI portable across runner image updates: avdmanager device ids vary,
  # while the generic Pixel profile is broadly available.
  if profile.start_with?("pixel_")
    return "pixel"
  end

  profile
end

data = YAML.load_file(DEVICE_POOL_FILE) || {}
profiles = data.fetch("profiles", {})
resolved = resolve_profile(verify_profile, profiles)

matrix = case platform
when "android"
  include_rows = []
  resolved["android"].each do |entry|
    label = entry["label"].to_s
    avd_name = entry["avd"].to_s
    api_level = entry["api"].to_s
    system_image = entry["system_image"].to_s
    next if label.empty? || avd_name.empty? || api_level.empty? || system_image.empty?

    system_image_parts = system_image.split(";")
    target = system_image_parts[2].to_s
    requested_arch = entry["abi"].to_s
    arch = android_arch_for_host(requested_arch, host_arch)
    effective_avd_name = requested_arch.empty? || requested_arch == arch ? avd_name : "#{avd_name}-#{arch}"

    include_rows << {
      "label" => label,
      "slug" => slugify(label),
      "api_level" => api_level,
      "target" => target.empty? ? "google_apis" : target,
      "arch" => arch,
      "device_profile" => android_ci_device_profile(entry["device_profile"]),
      "avd_name" => effective_avd_name
    }
  end
  { "include" => include_rows }
when "ios"
  include_rows = []
  resolved["ios"].each do |entry|
    label = entry["label"].to_s
    simulator = entry["simulator"].to_s
    device_class = entry["class"].to_s
    simulator = device_class if simulator.empty?
    next if label.empty? && simulator.empty?

    effective_label = label.empty? ? simulator : label
    include_rows << {
      "label" => effective_label,
      "slug" => slugify(effective_label),
      "device_class" => device_class.empty? ? "latest-phone" : device_class,
      "simulator_name" => simulator
    }
  end
  { "include" => include_rows }
else
  abort("unsupported platform: #{platform}")
end

puts JSON.generate(matrix)

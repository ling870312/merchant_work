#!/usr/bin/env ruby
# 仅用于 Simulator 构建（真机/IPA 工作流不调用本脚本）：
# 瘦身 SDK 里部分 framework 只含真机切片，Xcode 26 链接 Simulator 时会报
#   "building for 'iOS-simulator', but linking in object file ... built for 'iOS'"
# 这里先扫描工程实际链接的 framework，去掉不含模拟器切片（platform 7 缺失）的，
# 并把明细打印到日志，方便定位与复核。
require 'xcodeproj'
require 'shellwords'

APP_TARGET_TYPE = 'com.apple.product-type.application'
FRAMEWORK_SUFFIX = '.framework'
# iOS Simulator 在 LC_BUILD_VERSION 中的 platform 编号
SIMULATOR_PLATFORM = 7

project = Xcodeproj::Project.open('HBuilder-Hello/HBuilder-Hello.xcodeproj')
target = project.targets.find { |t| t.product_type == APP_TARGET_TYPE }
abort '!! app target not found（工程结构异常）' if target.nil?

def framework_dir_names(target)
  names = []
  target.frameworks_build_phase.files.each do |bf|
    ref = bf.file_ref
    next if ref.nil?
    name = ref.display_name.to_s
    name = File.basename(ref.path.to_s) if name.empty?
    names << name
  end
  target.copy_files_build_phases.each do |phase|
    phase.files.each do |bf|
      ref = bf.file_ref
      next if ref.nil?
      name = ref.display_name.to_s
      name = File.basename(ref.path.to_s) if name.empty?
      names << name
    end
  end
  names
end

def ldflag_framework_names(target)
  target.build_configurations.flat_map do |config|
    ldflags = config.build_settings['OTHER_LDFLAGS']
    values =
      case ldflags
      when Array then ldflags.map(&:to_s)
      when String then Shellwords.split(ldflags)
      else []
      end
    names = []
    values.each_with_index do |value, i|
      if value == '-framework' && values[i + 1]
        names << "#{values[i + 1]}#{FRAMEWORK_SUFFIX}"
      elsif value.start_with?('-framework')
        names << "#{value.sub('-framework', '')}#{FRAMEWORK_SUFFIX}"
      end
    end
    names
  end
end

def find_framework_dirs(framework_name)
  dirs = []
  %w[SDK HBuilder-Hello].each do |root|
    dirs.concat(Dir.glob(File.join(root, '**', framework_name)))
  end
  dirs.uniq
end

def simulator_support(binary)
  out = `xcrun otool -l #{Shellwords.escape(binary)} 2>/dev/null`
  return :unknown if out.strip.empty?
  out =~ /^\s*platform\s+#{SIMULATOR_PLATFORM}\s*$/ ? :yes : :no
end

def report(path, name)
  binary = File.join(path, File.basename(name, FRAMEWORK_SUFFIX))
  archs = `xcrun lipo -archs #{Shellwords.escape(binary)} 2>/dev/null`.strip
  support = File.file?(binary) ? simulator_support(binary) : :unknown
  archs = '?' if archs.empty?
  puts format('  %-40s archs=%-24s simulator=%s', name, archs, support)
  support
end

candidates = (framework_dir_names(target) + ldflag_framework_names(target))
             .select { |n| n.end_with?(FRAMEWORK_SUFFIX) }
             .uniq
             .sort

puts "Simulator 构建：待检查 framework #{candidates.length} 个"
to_remove = []
candidates.each do |name|
  dirs = find_framework_dirs(name)
  if dirs.empty?
    puts format('  %-40s 未在工程树中找到，跳过', name)
    next
  end
  results = dirs.map { |d| [d, report(d, name)] }
  if results.any? { |(_, r)| r == :yes }
    next
  end
  if results.all? { |(_, r)| r == :no }
    to_remove << name
    puts "  => 标记移除（无模拟器切片）: #{name}"
  else
    puts "  => 切片信息无法判定，保留: #{name}"
  end
end

removed = []

target.frameworks_build_phase.files.dup.each do |bf|
  ref = bf.file_ref
  next if ref.nil?
  name = ref.display_name.to_s
  name = File.basename(ref.path.to_s) if name.empty?
  next unless to_remove.include?(name)
  bf.remove_from_project
  removed << "link:#{name}"
end

target.copy_files_build_phases.each do |phase|
  phase.files.dup.each do |bf|
    ref = bf.file_ref
    next if ref.nil?
    name = ref.display_name.to_s
    name = File.basename(ref.path.to_s) if name.empty?
    next unless to_remove.include?(name)
    bf.remove_from_project
    removed << "copy(#{phase.name}):#{name}"
  end
end

target.build_configurations.each do |config|
  ldflags = config.build_settings['OTHER_LDFLAGS']
  next if ldflags.nil?

  case ldflags
  when Array
    values = ldflags.map(&:to_s)
    filtered = []
    i = 0
    while i < values.length
      if values[i] == '-framework' && i + 1 < values.length &&
         to_remove.include?("#{values[i + 1]}#{FRAMEWORK_SUFFIX}")
        removed << "ldflags:#{values[i + 1]}"
        i += 2
        next
      end
      if values[i].end_with?(FRAMEWORK_SUFFIX) && to_remove.include?(values[i])
        removed << "ldflags:#{values[i]}"
        i += 1
        next
      end
      filtered << values[i]
      i += 1
    end
    config.build_settings['OTHER_LDFLAGS'] = filtered
  when String
    updated = ldflags.dup
    to_remove.each do |name|
      base = name.sub(/#{Regexp.escape(FRAMEWORK_SUFFIX)}$/, '')
      before = updated.dup
      updated = updated.gsub(/-framework\s+#{Regexp.escape(base)}(\s|$)/, '\1')
      updated = updated.gsub(/(^|\s)#{Regexp.escape(name)}(\s|$)/, '\1\2')
      removed << "ldflags:#{base}" if updated != before
    end
    config.build_settings['OTHER_LDFLAGS'] = updated
  end
end

project.save
if removed.empty?
  puts 'Simulator 构建：所有已链接 framework 均含模拟器切片，无需处理'
else
  puts "Simulator 构建：已移除 #{removed.uniq.join(', ')}"
end

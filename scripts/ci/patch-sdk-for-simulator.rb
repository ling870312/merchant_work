#!/usr/bin/env ruby
# 仅用于 Simulator 构建（真机/IPA 工作流不调用本脚本）。
#
# 瘦身 SDK 里的部分 .a / .framework 只有真机切片（LC_BUILD_VERSION platform=2），
# Xcode 链接 Simulator 时会报：
#   "building for 'iOS-simulator', but linking in object file ... built for 'iOS'"
# 本脚本把 arm64 真机 Mach-O 的 platform 从 iOS(2) 改为 iOS Simulator(7)，
# 不改任何代码/符号，仅绕过链接器的平台校验。正式 IPA 不受影响。
require 'fileutils'
require 'tmpdir'
require 'shellwords'

LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25
PLATFORM_IOS = 2
PLATFORM_IOS_SIMULATOR = 7

$stats = Hash.new(0)
$version_min_only = []

def patch_thin_macho!(data)
  magic = data[0, 4] && data[0, 4].unpack1('V')
  return 0 unless [0xfeedfacf, 0xfeedface].include?(magic)

  is64 = magic == 0xfeedfacf
  header_size = is64 ? 32 : 28
  ncmds = data[16, 4].to_s.unpack1('V').to_i
  off = header_size
  changed = 0
  saw_version_min = false

  ncmds.times do
    cmd = data[off, 4].to_s.unpack1('V').to_i
    cmdsize = data[off + 4, 4].to_s.unpack1('V').to_i
    break if cmdsize < 8

    if cmd == LC_BUILD_VERSION
      platform = data[off + 8, 4].to_s.unpack1('V').to_i
      if platform == PLATFORM_IOS
        data[off + 8, 4] = [PLATFORM_IOS_SIMULATOR].pack('V')
        changed += 1
      end
    elsif cmd == LC_VERSION_MIN_IPHONEOS
      saw_version_min = true
    end
    off += cmdsize
  end

  $stats[:version_min] += 1 if saw_version_min && changed.zero?
  changed
end

def patch_macho_file!(path)
  data = File.binread(path)
  changed = 0

  if data[0, 4] && data[0, 4].unpack1('N') == 0xcafebabe
    nfat = data[4, 4].to_s.unpack1('N').to_i
    nfat.times do |i|
      base = 8 + i * 20
      offset = data[base + 8, 4].to_s.unpack1('N').to_i
      size = data[base + 12, 4].to_s.unpack1('N').to_i
      next if offset <= 0 || size <= 0 || offset + size > data.bytesize
      slice = data[offset, size]
      changed += patch_thin_macho!(slice)
      data[offset, size] = slice
    end
  else
    changed += patch_thin_macho!(data)
  end

  File.binwrite(path, data) if changed.positive?
  changed
end

def patch_archive!(path)
  return 0 unless File.binread(path, 8) == "!<arch>\n"

  members = `ar -t #{path.shellescape} 2>/dev/null`.lines.map(&:strip).reject(&:empty?)
  return 0 if members.empty?

  changed = 0
  Dir.mktmpdir do |dir|
    Dir.chdir(dir) do
      system('ar', '-x', path, out: File::NULL, err: File::NULL) || return(0)
      objects = members.select { |m| File.file?(m) }
      return 0 if objects.empty?
      objects.each { |obj| changed += patch_macho_file!(obj) }
      if changed.positive?
        tmp_archive = File.join(dir, 'patched.a')
        ok = system('xcrun', 'libtool', '-static', '-o', tmp_archive, *objects,
                    out: File::NULL, err: File::NULL)
        if ok
          FileUtils.cp(tmp_archive, path)
        else
          warn "::warning::静态库重新打包失败，保持原文件: #{path}"
        end
      end
    end
  end
  changed
end

roots = ['SDK', 'HBuilder-Hello']
archives = roots.flat_map { |r| Dir.glob(File.join(r, '**', '*.a')) }.uniq
machos = roots.flat_map do |r|
  Dir.glob(File.join(r, '**', '*.framework'))
     .reject { |fw| fw.include?('.xcframework/') }
     .map { |fw| File.join(fw, File.basename(fw, '.framework')) }
end.select { |f| File.file?(f) }
machos += roots.flat_map { |r| Dir.glob(File.join(r, '**', '*.dylib')) }

puts "Simulator 构建：开始修补真机专用二进制"
puts "  静态库: #{archives.length} 个"
puts "  Framework/dylib: #{machos.length} 个"

total = 0
archives.each_with_index do |path, idx|
  n = patch_archive!(path)
  total += n
  $stats[:archives] += 1 if n.positive?
  puts "  [#{idx + 1}/#{archives.length}] #{path}: #{n} 个对象改为 Simulator" if n.positive?
end

machos.each do |path|
  n = patch_macho_file!(path)
  total += n
  $stats[:frameworks] += 1 if n.positive?
  puts "  #{path}: #{n} 个切片改为 Simulator" if n.positive?
end

puts "Simulator 构建：修补完成，共 #{total} 处 platform=2 -> 7"
puts "  含改动的静态库: #{$stats[:archives]}，framework/dylib: #{$stats[:frameworks]}"
if $stats[:version_min].positive?
  puts "  ::warning::有 #{$stats[:version_min]} 个文件只含 LC_VERSION_MIN_IPHONEOS（无法就地改平台），若链接失败需另行处理"
end

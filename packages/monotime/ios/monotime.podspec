Pod::Spec.new do |s|
  s.name             = 'monotime'
  s.version          = '0.1.0'
  s.summary          = 'Tamper-resistant network time for Flutter.'
  s.description      = <<-DESC
    Anchors NTP + HTTPS-authenticated consensus to the hardware monotonic clock.
    No Rust, no NTS-KE complexity — just reliable, manipulation-proof time.
  DESC
  s.homepage         = 'https://github.com/Anurag-Bharati/dart-packages/tree/main/packages/monotime'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Anurag Bharati' => 'https://github.com/Anurag-Bharati' }
  s.source           = { :path => '.' }
  s.source_files     = 'monotime/Sources/monotime/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end

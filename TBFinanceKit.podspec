Pod::Spec.new do |s|
  s.name             = 'TBFinanceKit'
  s.version          = '0.1.0'
  s.summary          = '金融行情组件：股票/港股/美股/指数/板块/基金/期权实时行情与K线'

  s.description      = <<-DESC
  基于公开数据源（东方财富 push2 / 天天基金 mobapi / 新浪财经）的金融行情组件。
  支持多市场标的实时行情（定时轮询）、日/周/月 K 线（Core Graphics 手绘蜡烛图
  + 十字光标）、标的搜索、基金净值与详情、期权合约链。
  多域名 fallback 保证弱网可用，无三方依赖。
                       DESC

  s.homepage         = 'https://github.com/Yuan-l/TBFinanceKit.git'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Yuan-l' => '1013540016@qq.com' }
  s.source           = { :git => 'https://github.com/Yuan-l/TBFinanceKit.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'

  s.source_files = 'TBFinanceKit/Classes/**/*'

  s.frameworks = 'Foundation', 'UIKit'
end

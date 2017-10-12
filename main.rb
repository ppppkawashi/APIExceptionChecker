require 'faraday'
require 'uri'

class APIExceptionChecker
  def initialize(target_url:, skip_words:)
    @url = URI.parse(target_url)
    @skip_words = skip_words
  end
  
  def exec
    connection = build_connection()

    errors = []
    target_params.each do |param|
      next if @skip_words.include?(param) # 固定するパラメータはスキップする
      error_requests.each do |error_request|
        query = injected_error_request(param, error_request)
        response = connection.get(@url.path, query)
        puts query

        # 500ならエラー
        errors.push(build_error_message(status: response.status, url: @url.path, query: query)) if response.status == 500
      end
    end
    
    # エラーを表示
    errors.each do |error|
      write_error_log(error)
    end
  end

  private

  # コネクションを作る
  def build_connection
    Faraday.new(url: "http://#{@url.host}") do |builder|
      builder.request :url_encoded
      builder.adapter :net_http
    end
  end

  # ターゲットのパラメータ一覧を取得する
  def target_params
    @url.query.split("&").map { |param| param.split("=").first }.compact.map { |param| param }
  end
  
  # ターゲットの正常系リクエスト一覧を取得する
  def target_normal_requests
    @url.query.split("&").map do |q|
      query = q.split("=")
      query = "" if query[1].nil? # 値が無いクエリは空を代入
      {query[0] => query[1]}
    end.reduce { |q, param| q.merge(param) }
  end

  # エラーリクエスト一覧を取得する
  def error_requests
    error_requests = []
    File.foreach('./errors.txt') do |line|
      next if line[0] == "#" || line[0] == "\n"
      error_requests.push(line.gsub("\n", ""))
    end
    error_requests
  end

  # エラー入力を一つだけ注入した注入したリクエストを生成する
  def injected_error_request(param, error_request)
    query = target_normal_requests.dup
    query[param] = error_request
    query
  end

  # 200以外が返ってきた時のエラーメッセージを組み立てる
  def build_error_message(status:, url:, query:)
    query = query.map { |key, value| "#{key}=#{value}" }.join('&')
    "http://#{@url.host}#{@url.path}?#{query}"
  end
  
  # エラーログを作成する
  def write_error_log(error_str)
    File.open("error.log", "a") { |f| f.puts(error_str) }
  end
end

# エントリポイント
File.foreach('./urls.txt') do |line|
  next if line[0] == "#" || line[0] == "\n"
  APIExceptionChecker.new(target_url: line, skip_words: ARGV).exec
end

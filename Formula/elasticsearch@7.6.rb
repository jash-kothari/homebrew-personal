class ElasticsearchAT76 < Formula
  desc "Distributed search & analytics engine"
  homepage "https://www.elastic.co/products/elasticsearch"
  url "https://github.com/elastic/elasticsearch/archive/v7.6.2.tar.gz"
  sha256 "6ff4871dcae6954e13680aefc196da574a59a36418d06a7e095550ce81a370f8"

  depends_on "openjdk"

  def cluster_name
    "elasticsearch_#{ENV["USER"]}"
  end

  def install
    # Doesn't support brewed gradle
    system "./gradlew", ":distribution:archives:oss-no-jdk-darwin-tar:assemble"

    mkdir "tar" do
      # Extract the package to the tar directory
      system "tar", "--strip-components=1", "-xf",
        Dir["../distribution/archives/oss-no-jdk-darwin-tar/build/distributions/elasticsearch-oss-*.tar.gz"].first

      # Install into package directory
      libexec.install "bin", "lib", "modules"

      # Set up Elasticsearch for local development:
      inreplace "config/elasticsearch.yml" do |s|
        # 1. Give the cluster a unique name
        s.gsub!(/#\s*cluster\.name: .*/, "cluster.name: #{cluster_name}")

        # 2. Configure paths
        s.sub!(%r{#\s*path\.data: /path/to.+$}, "path.data: #{var}/lib/elasticsearch/")
        s.sub!(%r{#\s*path\.logs: /path/to.+$}, "path.logs: #{var}/log/elasticsearch/")
      end

      inreplace "config/jvm.options", %r{logs/gc.log}, "#{var}/log/elasticsearch/gc.log"

      # Move config files into etc
      (etc/"elasticsearch").install Dir["config/*"]
    end

    inreplace libexec/"bin/elasticsearch-env",
              "if [ -z \"$ES_PATH_CONF\" ]; then ES_PATH_CONF=\"$ES_HOME\"/config; fi",
              "if [ -z \"$ES_PATH_CONF\" ]; then ES_PATH_CONF=\"#{etc}/elasticsearch\"; fi"

    bin.install libexec/"bin/elasticsearch",
                libexec/"bin/elasticsearch-keystore",
                libexec/"bin/elasticsearch-plugin",
                libexec/"bin/elasticsearch-shard"
    bin.env_script_all_files(libexec/"bin", :JAVA_HOME => Formula["openjdk"].opt_prefix)
  end

  def post_install
    # Make sure runtime directories exist
    (var/"lib/elasticsearch_7.6").mkpath
    (var/"log/elasticsearch_7.6").mkpath
    ln_s etc/"elasticsearch_7.6", libexec/"config" unless (libexec/"config").exist?
    (var/"elasticsearch_7.6/plugins").mkpath
    ln_s var/"elasticsearch_7.6/plugins", libexec/"plugins" unless (libexec/"plugins").exist?
    # fix test not being able to create keystore because of sandbox permissions
    system bin/"elasticsearch-keystore", "create" unless (etc/"elasticsearch_7.6/elasticsearch.keystore").exist?
  end

  def caveats
    s = <<~EOS
      Data:    #{var}/lib/elasticsearch_7.6/
      Logs:    #{var}/log/elasticsearch_7.6/#{cluster_name}.log
      Plugins: #{var}/elasticsearch_7.6/plugins/
      Config:  #{etc}/elasticsearch_7.6/
    EOS

    s
  end

  plist_options :manual => "elasticsearch"

  def plist
    <<~EOS
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
        <dict>
          <key>KeepAlive</key>
          <false/>
          <key>Label</key>
          <string>#{plist_name}</string>
          <key>ProgramArguments</key>
          <array>
            <string>#{opt_bin}/elasticsearch</string>
          </array>
          <key>EnvironmentVariables</key>
          <dict>
          </dict>
          <key>RunAtLoad</key>
          <true/>
          <key>WorkingDirectory</key>
          <string>#{var}</string>
          <key>StandardErrorPath</key>
          <string>#{var}/log/elasticsearch.log</string>
          <key>StandardOutPath</key>
          <string>#{var}/log/elasticsearch.log</string>
        </dict>
      </plist>
    EOS
  end

  test do
    port = free_port
    pid = testpath/"pid"
    system bin/"elasticsearch", "-d", "-p", pid,
                                "-Ehttp.port=#{port}",
                                "-Epath.data=#{testpath}/data",
                                "-Epath.logs=#{testpath}/logs"
    sleep 10
    output = shell_output("curl -s -XGET localhost:#{port}/")
    assert_equal "oss", JSON.parse(output)["version"]["build_flavor"]

    system "#{bin}/elasticsearch-plugin", "list"
  end
end

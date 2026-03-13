# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "async/http/server"
require "protocol/http"

module AgentHarness
  # HTTP server for exposing Prometheus metrics endpoint
  # Runs on port 9090 by default
  class MetricsServer
    DEFAULT_PORT = 9090
    DEFAULT_HOST = "127.0.0.1"  # Secure default: localhost only

    attr_reader :port, :host, :metrics

    # @param metrics [Metrics] Metrics collector instance
    # @param port [Integer] Port to listen on
    # @param host [String] Host to bind to (default: 127.0.0.1 for security)
    def initialize(metrics:, port: DEFAULT_PORT, host: DEFAULT_HOST)
      @metrics = metrics
      @port = port
      @host = host
      @endpoint = nil
      @server = nil
    end

    # Start the metrics server
    # Blocks until stop() is called
    # @return [void]
    def start
      @endpoint = Async::HTTP::Endpoint.parse("http://#{@host}:#{@port}")

      app = build_app
      @server = Async::HTTP::Server.new(app, @endpoint)

      # Log startup
      puts({
        timestamp: Time.now.utc.iso8601,
        level: "info",
        event: "metrics_server.started",
        context: { host: @host, port: @port }
      }.to_json)

      @server.run
    end

    # Stop the metrics server
    # @return [void]
    def stop
      @server&.stop
    end

    private

    # Build a simple app handler
    # Async::HTTP passes a Request object
    def build_app
      lambda do |request|
        # request.path returns the path component (e.g., "/metrics")
        path = request.path.to_s

        case path
        when "/metrics"
          handle_metrics
        when "/health"
          handle_health
        else
          Protocol::HTTP::Response[404, {"content-type" => "text/plain"}, ["Not Found"]]
        end
      end
    end

    def handle_metrics
      body = @metrics.exposition_format

      Protocol::HTTP::Response[200, {"content-type" => "text/plain; version=0.0.4"}, [body]]
    rescue => e
      Protocol::HTTP::Response[500, {"content-type" => "text/plain"}, ["Error generating metrics: #{e.message}"]]
    end

    def handle_health
      Protocol::HTTP::Response[200, {"content-type" => "application/json"}, ['{"status":"healthy"}']]
    end
  end
end

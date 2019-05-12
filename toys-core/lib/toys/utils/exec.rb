# frozen_string_literal: true

# Copyright 2019 Daniel Azuma
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
;

require "logger"
require "shellwords"

module Toys
  module Utils
    ##
    # A service that executes subprocesses.
    #
    # This service provides a convenient interface for controlling spawned
    # processes and their streams. It also provides shortcuts for common cases
    # such as invoking Ruby in a subprocess or capturing output in a string.
    #
    # This class is not loaded by default. Before using it directly, you should
    # `require "toys/utils/exec"`
    #
    # ## Configuration options
    #
    # A variety of options can be used to control subprocesses. These include:
    #
    # *  **:env** (Hash) Environment variables to pass to the subprocess
    # *  **:logger** (Logger) Logger to use for logging the actual command.
    #    If not present, the command is not logged.
    # *  **:log_level** (Integer,false) Level for logging the actual command.
    #    Defaults to Logger::INFO if not present. You may also pass `false` to
    #    disable logging of the command.
    # *  **:log_cmd** (String) The string logged for the actual command.
    #    Defaults to the `inspect` representation of the command.
    # *  **:background** (Boolean) Runs the process in the background,
    #    returning a controller object instead of a result object.
    # *  **:in** Connects the input stream of the subprocess. See the section
    #    on stream handling.
    # *  **:out** Connects the standard output stream of the subprocess. See
    #    the section on stream handling.
    # *  **:err** Connects the standard error stream of the subprocess. See the
    #    section on stream handling.
    #
    # In addition, the following options recognized by `Process#spawn` are
    # supported.
    #
    # *  `:chdir`
    # *  `:close_others`
    # *  `:new_pgroup`
    # *  `:pgroup`
    # *  `:umask`
    # *  `:unsetenv_others`
    #
    # Any other options are ignored.
    #
    # Configuration options may be provided to any method that starts a
    # subprocess. You may also modify default values by calling
    # {Toys::Utils::Exec#configure_defaults}.
    #
    # ## Stream handling
    #
    # By default, subprocess streams are connected to the corresponding streams
    # in the parent process. You can change this behavior, redirecting streams
    # or providing ways to control them, using the `:in`, `:out`, and `:err`
    # options.
    #
    # Three general strategies are available for custom stream handling. First,
    # you may redirect to other streams such as files, IO objects, or Ruby
    # strings. Some of these options map directly to options provided by the
    # `Process#spawn` method. Second, you may use a controller to manipulate
    # the streams programmatically. Third, you may capture output stream data
    # and make it available in the result.
    #
    # Following is a full list of the stream handling options, along with how
    # to specify them using the `:in`, `:out`, and `:err` options.
    #
    # *  **Close the stream:** You may close the stream by passing `:close` as
    #    the option value. This is the same as passing `:close` to
    #    `Process#spawn`.
    # *  **Redirect to null:** You may redirect to a null stream by passing
    #    `:null` as the option value. This connects to a stream that is not
    #    closed but contains no data, i.e. `/dev/null` on unix systems. This is
    #    the default if the subprocess is run in the background.
    # *  **Inherit parent stream:** You may inherit the corresponding stream in
    #    the parent process by passing `:inherit` as the option value. This is
    #    the default if the subprocess is *not* run in the background.
    # *  **Redirect to a file:** You may redirect to a file. This reads from an
    #    existing file when connected to `:in`, and creates or appends to a
    #    file when connected to `:out` or `:err`. To specify a file, use the
    #    setting `[:file, "/path/to/file"]`. You may also, when writing a file,
    #    append an optional mode and permission code to the array. For
    #    example, `[:file, "/path/to/file", "a", 0644]`.
    # *  **Redirect to an IO object:** You may redirect to an IO object in the
    #    parent process, by passing the IO object as the option value. You may
    #    use any IO object. For example, you could connect the child's output
    #    to the parent's error using `out: $stderr`, or you could connect to an
    #    existing File stream. Unlike `Process#spawn`, this works for IO
    #    objects that do not have a corresponding file descriptor (such as
    #    StringIO objects). In such a case, a thread will be spawned to pipe
    #    the IO data through to the child process.
    # *  **Combine with another child stream:** You may redirect one child
    #    output stream to another, to combine them. To merge the child's error
    #    stream into its output stream, use `err: [:child, :out]`.
    # *  **Read from a string:** You may pass a string to the input stream by
    #    setting `[:string, "the string"]`. This works only for `:in`.
    # *  **Capture output stream:** You may capture a stream and make it
    #    available on the {Toys::Utils::Exec::Result} object, using the setting
    #    `:capture`. This works only for the `:out` and `:err` streams.
    # *  **Use the controller:** You may hook a stream to the controller using
    #    the setting `:controller`. You can then manipulate the stream via the
    #    controller. If you pass a block to {Toys::Utils::Exec#exec}, it yields
    #    the {Toys::Utils::Exec::Controller}, giving you access to streams.
    #
    class Exec
      ##
      # Create an exec service.
      #
      # @param [Hash] opts Initial default options.
      #
      def initialize(opts = {}, &block)
        @default_opts = Opts.new(&block).add(opts)
      end

      ##
      # Set default options
      #
      # @param [Hash] opts New default options to set
      #
      def configure_defaults(opts = {})
        @default_opts.add(opts)
        self
      end

      ##
      # Execute a command. The command may be given as a single string to pass
      # to a shell, or an array of strings indicating a posix command.
      #
      # If the process is not set to run in the background, and a block is
      # provided, a {Toys::Utils::Exec::Controller} will be yielded to it.
      #
      # @param [String,Array<String>] cmd The command to execute.
      # @param [Hash] opts The command options. See the section on
      #     configuration options in the {Toys::Utils::Exec} module docs.
      # @yieldparam controller [Toys::Utils::Exec::Controller] A controller
      #     for the subprocess streams.
      #
      # @return [Toys::Utils::Exec::Controller,Toys::Utils::Exec::Result] The
      #     subprocess controller or result, depending on whether the process
      #     is running in the background or foreground.
      #
      def exec(cmd, opts = {}, &block)
        exec_opts = Opts.new(@default_opts).add(opts)
        spawn_cmd =
          if cmd.is_a?(::Array)
            if cmd.size == 1 && cmd.first.is_a?(::String)
              [[cmd.first, exec_opts.config_opts[:argv0] || cmd.first]]
            else
              cmd
            end
          else
            [cmd]
          end
        executor = Executor.new(exec_opts, spawn_cmd, block)
        executor.execute
      end

      ##
      # Spawn a ruby process and pass the given arguments to it.
      #
      # If the process is not set to run in the background, and a block is
      # provided, a {Toys::Utils::Exec::Controller} will be yielded to it.
      #
      # @param [String,Array<String>] args The arguments to ruby.
      # @param [Hash] opts The command options. See the section on
      #     configuration options in the {Toys::Utils::Exec} module docs.
      # @yieldparam controller [Toys::Utils::Exec::Controller] A controller
      #     for the subprocess streams.
      #
      # @return [Toys::Utils::Exec::Controller,Toys::Utils::Exec::Result] The
      #     subprocess controller or result, depending on whether the process
      #     is running in the background or foreground.
      #
      def exec_ruby(args, opts = {}, &block)
        cmd = args.is_a?(::Array) ? [::RbConfig.ruby] + args : "#{::RbConfig.ruby} #{args}"
        log_cmd = args.is_a?(::Array) ? ["ruby"] + args : "ruby #{args}"
        exec(cmd, {argv0: "ruby", log_cmd: log_cmd}.merge(opts), &block)
      end
      alias ruby exec_ruby

      ##
      # Execute a proc in a fork.
      #
      # If the process is not set to run in the background, and a block is
      # provided, a {Toys::Utils::Exec::Controller} will be yielded to it.
      #
      # @param [Proc] func The proc to call.
      # @param [Hash] opts The command options. See the section on
      #     configuration options in the {Toys::Utils::Exec} module docs.
      # @yieldparam controller [Toys::Utils::Exec::Controller] A controller
      #     for the subprocess streams.
      #
      # @return [Toys::Utils::Exec::Controller,Toys::Utils::Exec::Result] The
      #     subprocess controller or result, depending on whether the process
      #     is running in the background or foreground.
      #
      def exec_proc(func, opts = {}, &block)
        exec_opts = Opts.new(@default_opts).add(opts)
        executor = Executor.new(exec_opts, func, block)
        executor.execute
      end

      ##
      # Execute a command. The command may be given as a single string to pass
      # to a shell, or an array of strings indicating a posix command.
      #
      # Captures standard out and returns it as a string.
      # Cannot be run in the background.
      #
      # If a block is provided, a {Toys::Utils::Exec::Controller} will be
      # yielded to it.
      #
      # @param [String,Array<String>] cmd The command to execute.
      # @param [Hash] opts The command options. See the section on
      #     configuration options in the {Toys::Utils::Exec} module docs.
      # @yieldparam controller [Toys::Utils::Exec::Controller] A controller
      #     for the subprocess streams.
      #
      # @return [String] What was written to standard out.
      #
      def capture(cmd, opts = {}, &block)
        exec(cmd, opts.merge(out: :capture, background: false), &block).captured_out
      end

      ##
      # Spawn a ruby process and pass the given arguments to it.
      #
      # Captures standard out and returns it as a string.
      # Cannot be run in the background.
      #
      # If a block is provided, a {Toys::Utils::Exec::Controller} will be
      # yielded to it.
      #
      # @param [String,Array<String>] args The arguments to ruby.
      # @param [Hash] opts The command options. See the section on
      #     configuration options in the {Toys::Utils::Exec} module docs.
      # @yieldparam controller [Toys::Utils::Exec::Controller] A controller
      #     for the subprocess streams.
      #
      # @return [String] What was written to standard out.
      #
      def capture_ruby(args, opts = {}, &block)
        ruby(args, opts.merge(out: :capture, background: false), &block).captured_out
      end

      ##
      # Execute a proc in a fork.
      #
      # Captures standard out and returns it as a string.
      # Cannot be run in the background.
      #
      # If a block is provided, a {Toys::Utils::Exec::Controller} will be
      # yielded to it.
      #
      # @param [Proc] func The proc to call.
      # @param [Hash] opts The command options. See the section on
      #     configuration options in the {Toys::Utils::Exec} module docs.
      # @yieldparam controller [Toys::Utils::Exec::Controller] A controller
      #     for the subprocess streams.
      #
      # @return [String] What was written to standard out.
      #
      def capture_proc(func, opts = {}, &block)
        exec_proc(func, opts.merge(out: :capture, background: false), &block).captured_out
      end

      ##
      # Execute the given string in a shell. Returns the exit code.
      # Cannot be run in the background.
      #
      # @param [String] cmd The shell command to execute.
      # @param [Hash] opts The command options. See the section on
      #     configuration options in the {Toys::Utils::Exec} module docs.
      # @yieldparam controller [Toys::Utils::Exec::Controller] A controller
      #     for the subprocess streams.
      #
      # @return [Integer] The exit code
      #
      def sh(cmd, opts = {}, &block)
        exec(cmd, opts.merge(background: false), &block).exit_code
      end

      ##
      # An internal helper class storing the configuration of a subprocess invocation
      # @private
      #
      class Opts
        ##
        # Option keys that belong to exec configuration
        # @private
        #
        CONFIG_KEYS = %i[
          argv0
          background
          cli
          env
          err
          in
          logger
          log_cmd
          log_level
          nonzero_status_handler
          out
        ].freeze

        ##
        # Option keys that belong to spawn configuration
        # @private
        #
        SPAWN_KEYS = %i[
          chdir
          close_others
          new_pgroup
          pgroup
          umask
          unsetenv_others
        ].freeze

        def initialize(parent = nil)
          if parent
            @config_opts = ::Hash.new { |_h, k| parent.config_opts[k] }
            @spawn_opts = ::Hash.new { |_h, k| parent.spawn_opts[k] }
          elsif block_given?
            @config_opts = ::Hash.new { |_h, k| yield k }
            @spawn_opts = ::Hash.new { |_h, k| yield k }
          else
            @config_opts = {}
            @spawn_opts = {}
          end
        end

        def add(config)
          config.each do |k, v|
            if CONFIG_KEYS.include?(k)
              @config_opts[k] = v
            elsif SPAWN_KEYS.include?(k) || k.to_s.start_with?("rlimit_")
              @spawn_opts[k] = v
            else
              raise ::ArgumentError, "Unknown key: #{k.inspect}"
            end
          end
          self
        end

        def delete(*keys)
          keys.each do |k|
            if CONFIG_KEYS.include?(k)
              @config_opts.delete(k)
            elsif SPAWN_KEYS.include?(k) || k.to_s.start_with?("rlimit_")
              @spawn_opts.delete(k)
            else
              raise ::ArgumentError, "Unknown key: #{k.inspect}"
            end
          end
          self
        end

        attr_reader :config_opts
        attr_reader :spawn_opts
      end

      ##
      # An object that controls a subprocess. This object is returned from an
      # execution running in the background, or is yielded to a control block
      # for an execution running in the foreground.
      # You may use this object to interact with the subcommand's streams,
      # send signals to the process, and get its result.
      #
      class Controller
        ## @private
        def initialize(controller_streams, captures, pid, join_threads, nonzero_status_handler)
          @in = controller_streams[:in]
          @out = controller_streams[:out]
          @err = controller_streams[:err]
          @captures = captures
          @pid = pid
          @join_threads = join_threads
          @nonzero_status_handler = nonzero_status_handler
          @wait_thread = ::Process.detach(pid)
          @result = nil
        end

        ##
        # Return the subcommand's standard input stream (which can be written
        # to), if the command was configured with `in: :controller`.
        # Returns `nil` otherwise.
        # @return [IO,nil]
        #
        attr_reader :in

        ##
        # Return the subcommand's standard output stream (which can be read
        # from), if the command was configured with `out: :controller`.
        # Returns `nil` otherwise.
        # @return [IO,nil]
        #
        attr_reader :out

        ##
        # Return the subcommand's standard error stream (which can be read
        # from), if the command was configured with `err: :controller`.
        # Returns `nil` otherwise.
        # @return [IO,nil]
        #
        attr_reader :err

        ##
        # Returns the process ID.
        # @return [Integer]
        #
        attr_reader :pid

        ##
        # Captures the remaining data in the given stream.
        # After calling this, do not read directly from the stream.
        #
        # @param [:out,:err] which Which stream to capture
        #
        def capture(which)
          stream = stream_for(which)
          @join_threads << ::Thread.new do
            begin
              @captures[which] = stream.read
            ensure
              stream.close
            end
          end
          self
        end

        ##
        # Captures the remaining data in the standard output stream.
        # After calling this, do not read directly from the stream.
        #
        def capture_out
          capture(:out)
        end

        ##
        # Captures the remaining data in the standard error stream.
        # After calling this, do not read directly from the stream.
        #
        def capture_err
          capture(:err)
        end

        ##
        # Redirects the remainder of the given stream.
        #
        # You may specify the stream as an IO or IO-like object, or as a file
        # specified by its path. If specifying a file, you may optionally
        # provide the mode and permissions for the call to `File#open`. You can
        # also specify the value `:null` to indicate the null file.
        #
        # After calling this, do not interact directly with the stream.
        #
        # @param [:in,:out,:err] which Which stream to redirect
        # @param [IO,StringIO,String,:null] io Where to redirect the stream
        # @param [Object...] io_args The mode and permissions for opening the
        #     file, if redirecting to/from a file.
        #
        def redirect(which, io, *io_args)
          io = ::File::NULL if io == :null
          if io.is_a?(::String)
            io_args = which == :in ? ["r"] : ["w"] if io_args.empty?
            io = ::File.open(io, *io_args)
          end
          stream = stream_for(which, allow_in: true)
          @join_threads << ::Thread.new do
            begin
              if which == :in
                ::IO.copy_stream(io, stream)
              else
                ::IO.copy_stream(stream, io)
              end
            ensure
              stream.close
              io.close
            end
          end
        end

        ##
        # Redirects the remainder of the standard input stream.
        #
        # You may specify the stream as an IO or IO-like object, or as a file
        # specified by its path. If specifying a file, you may optionally
        # provide the mode and permissions for the call to `File#open`. You can
        # also specify the value `:null` to indicate the null file.
        #
        # After calling this, do not interact directly with the stream.
        #
        # @param [IO,StringIO,String,:null] io Where to redirect the stream
        # @param [Object...] io_args The mode and permissions for opening the
        #     file, if redirecting from a file.
        #
        def redirect_in(io, *io_args)
          redirect(:in, io, *io_args)
        end

        ##
        # Redirects the remainder of the standard output stream.
        #
        # You may specify the stream as an IO or IO-like object, or as a file
        # specified by its path. If specifying a file, you may optionally
        # provide the mode and permissions for the call to `File#open`. You can
        # also specify the value `:null` to indicate the null file.
        #
        # After calling this, do not interact directly with the stream.
        #
        # @param [IO,StringIO,String,:null] io Where to redirect the stream
        # @param [Object...] io_args The mode and permissions for opening the
        #     file, if redirecting to a file.
        #
        def redirect_out(io, *io_args)
          redirect(:out, io, *io_args)
        end

        ##
        # Redirects the remainder of the standard error stream.
        #
        # You may specify the stream as an IO or IO-like object, or as a file
        # specified by its path. If specifying a file, you may optionally
        # provide the mode and permissions for the call to `File#open`.
        #
        # After calling this, do not interact directly with the stream.
        #
        # @param [IO,StringIO,String] io Where to redirect the stream
        # @param [Object...] io_args The mode and permissions for opening the
        #     file, if redirecting to a file.
        #
        def redirect_err(io, *io_args)
          redirect(:err, io, *io_args)
        end

        ##
        # Send the given signal to the process. The signal may be specified
        # by name or number.
        #
        # @param [Integer,String] sig The signal to send.
        #
        def kill(sig)
          ::Process.kill(sig, pid)
        end
        alias signal kill

        ##
        # Determine whether the subcommand is still executing
        #
        # @return [Boolean]
        #
        def executing?
          @wait_thread.status ? true : false
        end

        ##
        # Wait for the subcommand to complete, and return a result object.
        #
        # @param [Numeric,nil] timeout The timeout in seconds, or `nil` to
        #     wait indefinitely.
        # @return [Toys::Utils::Exec::Result,nil] The result object, or `nil`
        #     if a timeout occurred.
        #
        def result(timeout: nil)
          return nil unless @wait_thread.join(timeout)
          @result ||= begin
            close_streams
            @join_threads.each(&:join)
            status = @wait_thread.value
            if @nonzero_status_handler && status.exitstatus != 0
              @nonzero_status_handler.call(status)
            end
            Result.new(@captures[:out], @captures[:err], status)
          end
        end

        ##
        # Close all the controller's streams.
        # @private
        #
        def close_streams
          @in.close if @in && !@in.closed?
          @out.close if @out && !@out.closed?
          @err.close if @err && !@err.closed?
          self
        end

        private

        def stream_for(which, allow_in: false)
          stream = nil
          case which
          when :out
            stream = @out
            @out = nil
          when :err
            stream = @err
            @err = nil
          when :in
            if allow_in
              stream = @in
              @in = nil
            end
          else
            raise ::ArgumentError, "Unknown stream #{which}"
          end
          raise ::ArgumentError, "Stream #{which} not available" unless stream
          stream
        end
      end

      ##
      # The return result from a subcommand
      #
      class Result
        ## @private
        def initialize(out, err, status)
          @captured_out = out
          @captured_err = err
          @status = status
        end

        ##
        # Returns the captured output string, if the command was configured
        # with `out: :capture`. Returns `nil` otherwise.
        # @return [String,nil]
        #
        attr_reader :captured_out

        ##
        # Returns the captured error string, if the command was configured
        # with `err: :capture`. Returns `nil` otherwise.
        # @return [String,nil]
        #
        attr_reader :captured_err

        ##
        # Returns the status code object.
        # @return [Process::Status]
        #
        attr_reader :status

        ##
        # Returns the numeric status code.
        # @return [Integer]
        #
        def exit_code
          status.exitstatus
        end

        ##
        # Returns true if the subprocess terminated with a zero status.
        # @return [Boolean]
        #
        def success?
          exit_code.zero?
        end

        ##
        # Returns true if the subprocess terminated with a nonzero status.
        # @return [Boolean]
        #
        def error?
          !exit_code.zero?
        end
      end

      ##
      # An object that manages the execution of a subcommand
      # @private
      #
      class Executor
        def initialize(exec_opts, spawn_cmd, block)
          @fork_func = spawn_cmd.respond_to?(:call) ? spawn_cmd : nil
          @spawn_cmd = spawn_cmd.respond_to?(:call) ? nil : spawn_cmd
          @config_opts = exec_opts.config_opts
          @spawn_opts = exec_opts.spawn_opts
          @captures = {}
          @controller_streams = {}
          @join_threads = []
          @child_streams = []
          @parent_streams = []
          @block = block
          @default_stream = @config_opts[:background] ? :null : :inherit
        end

        def execute
          setup_in_stream
          setup_out_stream(:out)
          setup_out_stream(:err)
          log_command
          pid = @fork_func ? start_fork : start_process
          @child_streams.each(&:close)
          controller = Controller.new(@controller_streams, @captures, pid, @join_threads,
                                      @config_opts[:nonzero_status_handler])
          return controller if @config_opts[:background]
          begin
            @block&.call(controller)
          ensure
            controller.close_streams
          end
          controller.result
        end

        private

        def log_command
          logger = @config_opts[:logger]
          if logger && @config_opts[:log_level] != false
            cmd_str = @config_opts[:log_cmd]
            cmd_str ||= @spawn_cmd.size == 1 ? @spawn_cmd.first : @spawn_cmd.inspect if @spawn_cmd
            logger.add(@config_opts[:log_level] || ::Logger::INFO, cmd_str) if cmd_str
          end
        end

        def start_process
          args = []
          args << @config_opts[:env] if @config_opts[:env]
          args.concat(@spawn_cmd)
          ::Process.spawn(*args, @spawn_opts)
        end

        def start_fork
          pid = ::Process.fork
          return pid unless pid.nil?
          exit_code = -1
          begin
            setup_env_within_fork
            setup_streams_within_fork
            exit_code = run_fork_func
          rescue ::SystemExit => e
            exit_code = e.status
          rescue ::Exception => e # rubocop:disable Lint/RescueException
            warn(([e.inspect] + e.backtrace).join("\n"))
          ensure
            ::Kernel.exit!(exit_code)
          end
        end

        def run_fork_func
          catch(:result) do
            if @spawn_opts[:chdir]
              ::Dir.chdir(@spawn_opts[:chdir]) { @fork_func.call(@config_opts) }
            else
              @fork_func.call(@config_opts)
            end
            0
          end
        end

        def setup_env_within_fork
          if @config_opts[:unsetenv_others]
            ::ENV.each_key do |k|
              ::ENV.delete(k) unless @config_opts.key?(k)
            end
          end
          (@config_opts[:env] || {}).each { |k, v| ::ENV[k.to_s] = v.to_s }
        end

        def setup_streams_within_fork
          @parent_streams.each(&:close)
          setup_in_stream_within_fork(@spawn_opts[:in], $stdin)
          setup_out_stream_within_fork(@spawn_opts[:out], $stdout)
          setup_out_stream_within_fork(@spawn_opts[:err], $stderr)
        end

        def setup_in_stream_within_fork(stream, stdstream)
          in_stream =
            case stream
            when ::Integer
              ::IO.open(stream)
            when ::Array
              ::File.open(*stream)
            when ::String
              ::File.open(stream, "r")
            when :close
              :close
            else
              stream if stream.respond_to?(:write)
            end
          if in_stream == :close
            stdstream.close
          elsif in_stream
            stdstream.reopen(in_stream)
          end
        end

        def setup_out_stream_within_fork(stream, stdstream)
          out_stream =
            case stream
            when ::Integer
              ::IO.open(stream)
            when ::Array
              interpret_out_array_within_fork(stream)
            when ::String
              ::File.open(stream, "w")
            when :close
              :close
            else
              stream if stream.respond_to?(:write)
            end
          if out_stream == :close
            stdstream.close
          elsif out_stream
            stdstream.reopen(out_stream)
            stdstream.sync = true
          end
        end

        def interpret_out_array_within_fork(stream)
          if stream.first == :child
            if stream[1] == :err
              $stderr
            elsif stream[1] == :out
              $stdout
            end
          else
            ::File.open(*stream)
          end
        end

        def setup_in_stream
          setting = @config_opts[:in] || @default_stream
          return unless setting
          case setting
          when ::Symbol
            setup_in_stream_of_type(setting, [])
          when ::Integer
            setup_in_stream_of_type(:parent, [setting])
          when ::String
            setup_in_stream_of_type(:file, [setting])
          when ::IO, ::StringIO
            interpret_in_io(setting)
          when ::Array
            interpret_in_array(setting)
          else
            raise "Unknown value for in: #{setting.inspect}"
          end
        end

        def interpret_in_io(setting)
          if setting.fileno.is_a?(::Integer)
            setup_in_stream_of_type(:parent, [setting.fileno])
          else
            setup_in_stream_of_type(:copy_io, [setting])
          end
        end

        def interpret_in_array(setting)
          case setting.first
          when ::Symbol
            setup_in_stream_of_type(setting.first, setting[1..-1])
          when ::String
            setup_in_stream_of_type(:file, setting)
          else
            raise "Unknown value for in: #{setting.inspect}"
          end
        end

        def setup_in_stream_of_type(type, args)
          case type
          when :controller
            @controller_streams[:in] = make_in_pipe
          when :null
            make_null_stream(:in, "r")
          when :inherit
            @spawn_opts[:in] = :in
          when :close
            @spawn_opts[:in] = type
          when :parent
            @spawn_opts[:in] = args.first
          when :child
            @spawn_opts[:in] = [:child, args.first]
          when :string
            write_string_thread(args.first.to_s)
          when :copy_io
            copy_to_in_thread(args.first)
          when :file
            interpret_in_file(args)
          else
            raise "Unknown type for in: #{type.inspect}"
          end
        end

        def interpret_in_file(args)
          raise "Expected only file name" unless args.size == 1 && args.first.is_a?(::String)
          @spawn_opts[:in] = args + [::File::RDONLY]
        end

        def setup_out_stream(key)
          setting = @config_opts[key] || @default_stream
          case setting
          when ::Symbol
            setup_out_stream_of_type(key, setting, [])
          when ::Integer
            setup_out_stream_of_type(key, :parent, [setting])
          when ::String
            setup_out_stream_of_type(key, :file, [setting])
          when ::IO, ::StringIO
            interpret_out_io(key, setting)
          when ::Array
            interpret_out_array(key, setting)
          else
            raise "Unknown value for #{key}: #{setting.inspect}"
          end
        end

        def interpret_out_io(key, setting)
          if setting.fileno.is_a?(::Integer)
            setup_out_stream_of_type(key, :parent, [setting.fileno])
          else
            setup_out_stream_of_type(key, :copy_io, [setting])
          end
        end

        def interpret_out_array(key, setting)
          case setting.first
          when ::Symbol
            setup_out_stream_of_type(key, setting.first, setting[1..-1])
          when ::String
            setup_out_stream_of_type(key, :file, setting)
          else
            raise "Unknown value for #{key}: #{setting.inspect}"
          end
        end

        def setup_out_stream_of_type(key, type, args)
          case type
          when :controller
            @controller_streams[key] = make_out_pipe(key)
          when :null
            make_null_stream(key, "w")
          when :inherit
            @spawn_opts[key] = key
          when :close, :out, :err
            @spawn_opts[key] = type
          when :parent
            @spawn_opts[key] = args.first
          when :child
            @spawn_opts[key] = [:child, args.first]
          when :capture
            capture_stream_thread(key)
          when :copy_io
            copy_from_out_thread(key, args.first)
          when :file
            interpret_out_file(key, args)
          else
            raise "Unknown type for #{key}: #{type.inspect}"
          end
        end

        def interpret_out_file(key, args)
          raise "Expected file name" if args.empty? || !args.first.is_a?(::String)
          raise "Too many file arguments" if args.size > 3
          @spawn_opts[key] = args.size == 1 ? args.first : args
        end

        def make_null_stream(key, mode)
          f = ::File.open(::File::NULL, mode)
          @spawn_opts[key] = f
          @child_streams << f
        end

        def make_in_pipe
          r, w = ::IO.pipe
          @spawn_opts[:in] = r
          @child_streams << r
          @parent_streams << w
          w.sync = true
          w
        end

        def make_out_pipe(key)
          r, w = ::IO.pipe
          @spawn_opts[key] = w
          @child_streams << w
          @parent_streams << r
          r
        end

        def write_string_thread(string)
          stream = make_in_pipe
          @join_threads << ::Thread.new do
            begin
              stream.write string
            ensure
              stream.close
            end
          end
        end

        def copy_to_in_thread(io)
          stream = make_in_pipe
          @join_threads << ::Thread.new do
            begin
              ::IO.copy_stream(io, stream)
            ensure
              stream.close
              io.close
            end
          end
        end

        def copy_from_out_thread(key, io)
          stream = make_out_pipe(key)
          @join_threads << ::Thread.new do
            begin
              ::IO.copy_stream(stream, io)
            ensure
              stream.close
              io.close
            end
          end
        end

        def capture_stream_thread(key)
          stream = make_out_pipe(key)
          @join_threads << ::Thread.new do
            begin
              @captures[key] = stream.read
            ensure
              stream.close
            end
          end
        end
      end
    end
  end
end

require "execjs/runtime"

module ExecJS
  class DynJSRuntime < Runtime
    class Context < Runtime::Context
      def initialize(runtime, source = "")
        source = encode(source)
        @dynjs = runtime.dynjs
        @context = Java::OrgDynjsRuntime::ExecutionContext.create_global_execution_context(@dynjs)
        @dynjs.evaluate(@context, source, false, false)
      end

      def exec(source, options = {})
        source = encode(source)

        if /\S/ =~ source
          eval "(function(){#{source}})()", options
        end
      end

      def eval(source, options = {})
        source = encode(source)

        if /\S/ =~ source
          unbox @dynjs.evaluate(@context, "(#{source})", false, false)
        end
      rescue Java::OrgDynjsException::ThrowException => e
        if e.message =~ /^SyntaxError/
          raise RuntimeError, e.message
        else
          raise ProgramError, e.message
        end
      end

      def call(properties, *args)
        function = @dynjs.evaluate(@context, properties, false, false)
        # JRuby gets a bit confused on the overloaded varargs call method
        # unbox @context.call(function, function, *args)
        unbox @context.java_send(:call, [org.dynjs.runtime.JSFunction.java_class,
                                         java.lang.Object, [].to_java.java_class],
                                 function, function, args)
      rescue Java::OrgDynjsException::ThrowException => e
        if e.message =~ /^SyntaxError/
          raise RuntimeError, e.message
        else
          raise ProgramError, e.message
        end
      end

      def unbox(value)
        case value
        when Java::OrgDynjsRuntime::Types::Null, Java::OrgDynjsRuntime::Types::Undefined then nil
        when Java::OrgDynjsRuntime::DynArray then
          length = value.get(@context, 'length')
          length.times.map { |i| unbox value.get(@context, "#{i}") }
        when Java::OrgDynjsRuntime::JSFunction then
          unbox value.call(@context)
        when Java::OrgDynjsRuntime::DynObject then
          property_names = value.get_own_property_names.to_list
          property_names.inject({}) do |hash, name|
            property_value = unbox value.get(@context, name)
            hash[name] = property_value unless property_value.nil?
            hash
          end
        else
          value
        end
      end
    end

    def dynjs
      unless defined? @dynjs
        config = Java::OrgDynjs::Config.new(JRuby.runtime.jruby_class_loader)
        @dynjs = Java::OrgDynjsRuntime::DynJS.new(config)
      end
      @dynjs
    end

    def name
      "dynjs (DynJS)"
    end

    def available?
      require "java"
      # TODO: A dynjs rubygem needs to be made and required here.
      # A lot of the other code in this file needs to be moved into that
      # gem so it's not interacting with java classes directly from execjs.
      if ENV['DYNJS_JAR']
        require ENV['DYNJS_JAR']
        Java::OrgDynjs::Config.new
        true
      else
        $stderr.puts "For now, you must set the DYNJS_JAR environment variable"
        false
      end
    rescue LoadError
      false
    rescue NameError
      $stderr.puts "DynJS requires Java 7 and you appear to be using an earlier version"
      false
    end
  end
end

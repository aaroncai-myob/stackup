require "stackup/error_handling"

module Stackup

  # An abstraction of a CloudFormation change-set.
  #
  class ChangeSet

    def initialize(name, stack)
      @name = name
      @stack = stack
    end

    attr_reader :name
    attr_reader :stack

    include ErrorHandling

    # Create the change-set.
    #
    # Refer +Aws::CloudFormation::Client#create_change_set+
    #   (see http://docs.aws.amazon.com/sdkforruby/api/Aws/CloudFormation/Client.html#create_change_set-instance_method)
    #
    # @param [Hash] options change-set options
    # @option options [Array<String>] :capabilities (CAPABILITY_NAMED_IAM)
    #   list of capabilities required for stack template
    # @option options [String] :description
    #   change-set description
    # @option options [String] :notification_arns
    #   ARNs for the Amazon SNS topics associated with this stack
    # @option options [Hash, Array<Hash>] :parameters
    #   stack parameters, either as a Hash, or an Array of
    #   +Aws::CloudFormation::Types::Parameter+ structures
    # @option options [Hash, Array<Hash>] :tags
    #   stack tags, either as a Hash, or an Array of
    #   +Aws::CloudFormation::Types::Tag+ structures
    # @option options [Array<String>] :resource_types
    #   resource types that you have permissions to work with
    # @option options [Hash] :template
    #   stack template, as Ruby data
    # @option options [String] :template_body
    #   stack template, as JSON or YAML
    # @option options [String] :template_url
    #   location of stack template
    # @option options [boolean] :use_previous_template
    #   if true, reuse the existing template
    # @option options [boolean] :force
    #   if true, delete any existing change-set of the same name
    #
    # @return [String] change-set id
    # @raise [Stackup::NoSuchStack] if the stack doesn't exist
    #
    def create(options = {})
      options = options.dup
      options[:stack_name] = stack.name
      options[:change_set_name] = name
      options[:change_set_type] = stack.exists? ? "UPDATE" : "CREATE"
      force = options.delete(:force)
      if (template_data = options.delete(:template))
        options[:template_body] = MultiJson.dump(template_data)
      end
      if (parameters = options[:parameters])
        options[:parameters] = Parameters.new(parameters).to_a
      end
      if (tags = options[:tags])
        options[:tags] = normalize_tags(tags)
      end
      options[:capabilities] ||= ["CAPABILITY_NAMED_IAM"]
      delete if force
      handling_cf_errors do
        cf_client.create_change_set(options)
        loop do
          current = describe_change_set
          logger.debug("change_set_status=#{current.status}")
          case current.status
          when /COMPLETE/
            return current.status
          when "FAILED"
            logger.error(current.status_reason)
            fail StackUpdateError, "change-set creation failed" if status == "FAILED"
          end
          sleep(wait_poll_interval)
        end
        status
      end
    end

    # Execute the change-set.
    #
    # @return [String] resulting stack status
    # @raise [Stackup::NoSuchChangeSet] if the change-set doesn't exist
    # @raise [Stackup::NoSuchStack] if the stack doesn't exist
    # @raise [Stackup::StackUpdateError] if operation fails
    #
    def execute
      modify_stack("UPDATE_COMPLETE", "update failed") do
        cf_client.execute_change_set(:stack_name => stack.name, :change_set_name => name)
      end
    end

    # Delete a change-set.
    #
    # @raise [Stackup::NoSuchStack] if the stack doesn't exist
    #
    def delete
      handling_cf_errors do
        cf_client.delete_change_set(:stack_name => stack.name, :change_set_name => name)
      end
      nil
    end

    def status
      describe_change_set.status
    end

    private

    def describe_change_set
      handling_cf_errors do
        cf_client.describe_change_set(:stack_name => stack.name, :change_set_name => name)
      end
    end

    def cf_client
      stack.send(:cf_client)
    end

    def modify_stack(*args, &block)
      stack.send(:modify_stack, *args, &block)
    end

    def normalize_tags(tags)
      stack.send(:normalize_tags, tags)
    end

    def logger
      stack.send(:logger)
    end

    def wait_poll_interval
      stack.send(:wait_poll_interval)
    end

  end

end

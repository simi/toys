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

module Toys
  module DSL
    ##
    # DSL for a flag definition block. Lets you set flag attributes in a block
    # instead of a long series of keyword arguments.
    #
    # These directives are available inside a block passed to
    # {Toys::DSL::Tool#flag}.
    #
    class Flag
      ## @private
      def initialize(flags, accept, default, handler, report_collisions,
                     group, desc, long_desc, display_name)
        @flags = flags
        @accept = accept
        @default = default
        @handler = handler
        @report_collisions = report_collisions
        @group = group
        @desc = desc
        @long_desc = long_desc || []
        @display_name = display_name
      end

      ##
      # Add flags in OptionParser format. This may be called multiple times,
      # and the results are cumulative.
      #
      # @param [String...] flags
      # @return [Toys::DSL::Flag] self, for chaining.
      #
      def flags(*flags)
        @flags += flags
        self
      end

      ##
      # Set the OptionParser acceptor.
      #
      # @param [Object] accept
      # @return [Toys::DSL::Flag] self, for chaining.
      #
      def accept(accept)
        @accept = accept
        self
      end

      ##
      # Set the default value.
      #
      # @param [Object] default
      # @return [Toys::DSL::Flag] self, for chaining.
      #
      def default(default)
        @default = default
        self
      end

      ##
      # Set the optional handler for setting/updating the value when a flag is
      # parsed. A handler should be a Proc taking two arguments, the new given
      # value and the previous value, and it should return the new value that
      # should be set. You may pass the handler as a Proc (or an object
      # responding to the `call` method) or you may pass a block.
      #
      # @param [Proc] handler
      # @return [Toys::DSL::Flag] self, for chaining.
      #
      def handler(handler = nil, &block)
        @handler = handler || block
        self
      end

      ##
      # Set whether to raise an exception if a flag is requested that is
      # already in use or marked as disabled.
      #
      # @param [Boolean] setting
      # @return [Toys::DSL::Flag] self, for chaining.
      #
      def report_collisions(setting)
        @report_collisions = setting
        self
      end

      ##
      # Set the short description. See {Toys::DSL::Tool#desc} for the allowed
      # formats.
      #
      # @param [String,Array<String>,Toys::WrappableString] desc
      # @return [Toys::DSL::Flag] self, for chaining.
      #
      def desc(desc)
        @desc = desc
        self
      end

      ##
      # Adds to the long description. This may be called multiple times, and
      # the results are cumulative. See {Toys::DSL::Tool#long_desc} for the
      # allowed formats.
      #
      # @param [String,Array<String>,Toys::WrappableString...] long_desc
      # @return [Toys::DSL::Flag] self, for chaining.
      #
      def long_desc(*long_desc)
        @long_desc += long_desc
        self
      end

      ##
      # Set the group. A group may be set by name or group object. Setting
      # `nil` selects the default group.
      #
      # @param [String,Symbol,Toys::Definition::FlagGroup,nil] group
      # @return [Toys::DSL::Flag] self, for chaining.
      #
      def group(group)
        @group = group
        self
      end

      ##
      # Set the display name. This may be used in help text and error messages.
      #
      # @param [String] display_name
      # @return [Toys::DSL::Flag] self, for chaining.
      #
      def display_name(display_name)
        @display_name = display_name
        self
      end

      ## @private
      def _add_to(tool, key)
        tool.add_flag(key, @flags,
                      accept: @accept, default: @default, handler: @handler,
                      report_collisions: @report_collisions, group: @group,
                      desc: @desc, long_desc: @long_desc, display_name: @display_name)
      end
    end
  end
end

# frozen_string_literal: true

# Base class for all service objects using ActiveInteraction.
#
# Service objects encapsulate business logic and keep controllers and models slim.
# They provide:
# - Input validation via typed filters (string, integer, model, etc.)
# - Composition of complex operations
# - Consistent error handling via errors collection
# - Transaction support
#
# Usage:
#   class MyService < ApplicationService
#     string :name
#     integer :age, default: nil
#
#     def execute
#       # Business logic here
#       # Return value becomes the result
#     end
#   end
#
#   outcome = MyService.run(name: "Alice", age: 30)
#   if outcome.valid?
#     outcome.result # => return value from execute
#   else
#     outcome.errors # => validation errors
#   end
#
# See: https://github.com/AaronLasseigne/active_interaction
class ApplicationService < ActiveInteraction::Base
end

require 'bigdecimal'

module ArDocStore
  module AttributeTypes
    class DecimalAttribute <BaseAttribute

      def build
        key = attribute.to_sym
        default_value = BigDecimal(default) if default
        model.class_eval do
          store_accessor json_column, key
          define_method key, -> {
            value = read_store_attribute(json_column,key)
            value = BigDecimal(value) unless value.nil? || value.empty?
            value or default_value
          }
          define_method "#{key}=".to_sym, -> (value) {
            value = nil if value == ''
            write_store_attribute(json_column, key, value.to_s)
          }
          add_ransacker(key, 'text')
        end
      end

      def type
        :decimal
      end
    end
  end
end

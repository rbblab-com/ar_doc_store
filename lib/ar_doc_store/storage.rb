module ArDocStore
  module Storage
    
    def self.included(mod)
      
      mod.class_attribute :virtual_attributes
      mod.virtual_attributes ||= HashWithIndifferentAccess.new
      
      mod.send :include, InstanceMethods
      mod.send :extend, ClassMethods
    end
    
    module InstanceMethods
      
      def write_attribute(name, value)
        if is_stored_attribute?(name)
          write_store_attribute :data, attribute_name_from_foreign_key(name), value
        else
          super
        end
      end

      def read_attribute(name)
        if is_stored_attribute?(name)
          read_store_attribute :data, attribute_name_from_foreign_key(name)
        else
          super
        end
      end

      private
      
      def is_stored_attribute?(name)
        name = name.to_sym
        is_store_accessor_method?(name) || name =~ /data\-\>\>/
      end

      def is_store_accessor_method?(name)
        name = name.to_sym
        self.class.stored_attributes[:data] && self.class.stored_attributes[:data].include?(name)
      end

      def attribute_name_from_foreign_key(name)
        is_store_accessor_method?(name) ? name : name.match(/\'(\w+)\'/)[0].gsub("'", '')
      end

      def clean_attribute_names_for_arel(attribute_names)
        attribute_names.reject{|attribute_name| is_stored_attribute?(attribute_name)}
      end

      # Overridden otherwise insert and update queries get fooled into thinking that stored attributes are real columns.
      def arel_attributes_with_values_for_create(attribute_names) #:nodoc:
        super clean_attribute_names_for_arel(attribute_names)
      end

      # Overridden otherwise insert and update queries get fooled into thinking that stored attributes are real columns.
      def arel_attributes_with_values_for_update(attribute_names) #:nodoc:
        super clean_attribute_names_for_arel(attribute_names)
      end
    end
    
    module ClassMethods
      
      def attribute(name, *args)
        type = args.shift if args.first.is_a?(Symbol)
        options = args.extract_options!
        type ||= options.delete(:as) || :string
        class_name = ArDocStore.mappings[type] || "ArDocStore::AttributeTypes::#{type.to_s.classify}Attribute"
        raise "Invalid attribute type: #{name}" unless const_defined?(class_name)
        class_name = class_name.constantize
        class_name.build self, name, options
        define_virtual_attribute_method name
      end

      #:nodoc:
      def add_ransacker(key, predicate = nil)
        return unless respond_to?(:ransacker)
        ransacker key do
          sql = "(data->>'#{key}')"
          if predicate
            sql = "#{sql}::#{predicate}"
          end
          Arel.sql(sql)
        end
      end

      #:nodoc:
      def store_attributes(typecast_method, predicate=nil, attributes=[], default_value=nil)
        attributes = [attributes] unless attributes.respond_to?(:each)
        attributes.each do |key|
          store_accessor :data, key
          add_ransacker(key, predicate)
          if typecast_method.is_a?(Symbol)
            store_attribute_from_symbol typecast_method, key, default_value
          else
            store_attribute_from_class typecast_method, key
          end
        end
      end

      #:nodoc:
      def store_attribute_from_symbol(typecast_method, key, default_value)
        define_method key.to_sym, -> { 
          value = read_store_attribute(:data, key)
          if value
            value.public_send(typecast_method)
          elsif default_value
            write_default_store_attribute(key, default_value)
            default_value
          end
        }
        define_method "#{key}=".to_sym, -> (value) {
          if value == '' || value.nil?
            write_store_attribute :data, key, nil
          else
            write_store_attribute(:data, key, value.public_send(typecast_method))
          end
        }
      end
      
      # TODO: add default value support. 
      # Default ought to be a hash of attributes, 
      # also accept a proc that receives the newly initialized object
      def store_attribute_from_class(class_name, key)
        define_method key.to_sym, -> {
          ivar = "@#{key}"
          instance_variable_get(ivar) || begin
            item = read_store_attribute(:data, key)
            class_name = class_name.constantize if class_name.respond_to?(:constantize)
            item = class_name.new(item) unless item.is_a?(class_name)
            instance_variable_set ivar, item
          end
        }
        define_method "#{key}=".to_sym, -> (value) {
          ivar = "@#{key}"
          existing = public_send(key)
          class_name = class_name.constantize if class_name.respond_to?(:constantize)
          if value == '' || !value
            value = nil
          elsif !value.is_a?(class_name)
            value = existing.apply_attributes(value)
          end
          instance_variable_set ivar, value
          write_store_attribute :data, key, value
        }
      end
      
      # Pretty much the same as define_attribute_method but skipping the matches that create read and write methods
      def define_virtual_attribute_method(attr_name)
        attr_name = attr_name.to_s
        attribute_method_matchers.each do |matcher|
          method_name = matcher.method_name(attr_name)
          next if instance_method_already_implemented?(method_name)
          next if %w{attribute attribute= attribute_before_type_cast}.include? matcher.method_missing_target
          generate_method = "define_method_#{matcher.method_missing_target}"
          if respond_to?(generate_method, true)
            send(generate_method, attr_name)
          else
            define_proxy_call true, generated_attribute_methods, method_name, matcher.method_missing_target, attr_name.to_s
          end
        end
        attribute_method_matchers_cache.clear
      end
            
      # Allows you to define several string attributes at once. Deprecated.
      def string_attributes(*args)
        args.each do |arg|
          attribute arg, as: :string
        end
      end

      # Allows you to define several float attributes at once. Deprecated.
      def float_attributes(*args)
        args.each do |arg|
          attribute arg, as: :float
        end
      end

      # Allows you to define several integer attributes at once. Deprecated.
      def integer_attributes(*args)
        args.each do |arg|
          attribute arg, as: :integer
        end
      end

      # Allows you to define several boolean attributes at once. Deprecated.
      def boolean_attributes(*args)
        args.each do |arg|
          attribute arg, as: :boolean
        end
      end

      # Shorthand for attribute :name, as: :enumeration, values: %w{a b c}
      # Deprecated.
      def enumerates(field, *args)
        options = args.extract_options!
        options[:as] = :enumeration
        attribute field, options
      end

    
    end
    
  end
end
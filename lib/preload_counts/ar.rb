# This adds a scope to preload the counts of an association in one SQL query. 
#
# Consider the following code:
# Service.all.each{|s| puts s.incidents.acknowledged.count}
#
# Each time count is called, a db query is made to fetch the count. 
#
# Adding this to the Service class:
#
# preload_counts :incidents => [:acknowledged]
#
# will add a preload_incident_counts scope to preload the counts and add
# accessors to the class. So our codes becaumes
#
# Service.preload_incident_counts.all.each{|s| puts s.acknowledged_incidents_count}
#
# And only requires one DB query.
module PreloadCounts
  module ClassMethods
    def preload_counts(options)
      options = Array(options).inject({}) {|h, v| h[v] = []; h}  unless options.is_a?(Hash)
      options.each do |association, scopes|
        scopes = scopes + [nil]

        # Define singleton metho to load all counts
        name = "preload_#{association.to_s.singularize}_counts"
        singleton = class << self; self end
        singleton.send :define_method, name do
          sql = ['*'] + scopes_to_select(association, scopes)
          sql = sql.join(', ')
          scoped(:select => sql)
        end

        scopes.each do |scope|
          # Define accessor for each count
          accessor_name = find_accessor_name(association, scope)
          define_method accessor_name do
            result = send(association)
            result = result.send(scope) if scope
            (self[accessor_name] || result.size).to_i
          end
        end

      end
    end
    
    private
    def scopes_to_select(association, scopes)
      scopes.map do |scope|
        scope_to_select(association, scope)
      end
    end

    def scope_to_select(association, scope)
      resolved_association = association.to_s.singularize.camelize.constantize
      scope_sql = if scope
                    resolved_association.scopes[scope].call(resolved_association).send(:construct_finder_sql, {})
                  else
                    "1 = 1"
                  end
      # FIXME This is a really hacking way of getting the named_scope condition.
      # In Rails 3 we would have AREL to get to it. 
      condition = scope_sql.gsub(/^.*WHERE/, '')
      sql = <<-SQL
      (SELECT count(*) 
       FROM #{association} 
       WHERE #{association}.#{to_s.underscore}_id = #{table_name}.id AND 
       #{condition}) as #{find_accessor_name(association, scope)} 
      SQL
    end

    def find_accessor_name(association, scope)
      accessor_name = "#{association}_count"
      accessor_name = "#{scope}_" + accessor_name if scope
      accessor_name
    end
  end

  module InstanceMethods
  end

  def self.included(receiver)
    receiver.extend ClassMethods
    receiver.send :include, InstanceMethods
  end
end

ActiveRecord::Base.class_eval { include PreloadCounts }

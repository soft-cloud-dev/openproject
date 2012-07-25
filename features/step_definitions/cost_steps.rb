Given /^the project "([^\"]+)" has (\d+) [Cc]ost(?: )?[Ee]ntr(?:ies|y)$/ do |project, count|
  p = Project.find_by_name(project) || Project.find_by_identifier(project)
  as_admin count do
    ce = CostEntry.generate
    ce.project = p
    ce.issue = Issue.generate_for_project!(p)
    ce.save!
  end
end

Given /^there is 1 cost type with the following:$/ do |table|
  ct = CostType.generate
  send_table_to_object(ct, table, {
    :cost_rate => Proc.new do |o,v|
      CostRate.generate.tap do |cr|
        cr.rate = v
        cr.cost_type = o
      end.save!
    end,
    :name => Proc.new do |o,v|
      o.name = v
      o.unit = v
      o.unit_plural = "#{v}s"
      o.save!
    end})
end

Given /^there (?:is|are) (\d+) (default )?hourly rate[s]? with the following:$/ do |num, is_default, table|
  if is_default
    hr = DefaultHourlyRate.spawn
  else
    hr = HourlyRate.spawn
  end
  send_table_to_object(hr, table, {
    :user => Proc.new do |rate, value|
      # I am sorry, but it didn't seem to work with any less saving!
      rate.save!
      rate.reload.save!
      unless rate.project.nil? || User.find_by_login(value).projects.include?(rate.project)
        rate.save!
        rate.update_attribute :project_id, User.find_by_login(value).projects(:order => "id ASC").last.id
        rate.reload.save!
      end
      rate.update_attribute :user_id, User.find_by_login(value).id
      rate.reload.save!
    end,
    :valid_from => Proc.new do |rate, value|
      # This works for definitions like "2 years ago"
      number, time_unit, tempus = value.split
      time = number.to_i.send(time_unit.to_sym).send(tempus.to_sym)
      rate.update_attribute :valid_from, time
    end })
end

Given /^the [Uu]ser "([^\"]*)" has (\d+) [Cc]ost(?: )?[Ee]ntr(?:ies|y)$/ do |user, count|
  u = User.find_by_login user
  p = u.projects.last
  i = Issue.generate_for_project!(p)
  as_admin count do
    ce = CostEntry.spawn
    ce.user = u
    ce.project = p
    ce.issue = i
    ce.save!
  end
end

Given /^the project "([^\"]+)" has (\d+) [Cc]ost(?: )?[Ee]ntr(?:ies|y) with the following:$/ do |project, count, table|
  p = Project.find_by_name(project) || Project.find_by_identifier(project)
  i = Issue.generate_for_project!(p)
  as_admin count do
    ce = CostEntry.generate
    ce.project = p
    ce.issue = i
    send_table_to_object(ce, table)
    ce.save!
  end
end

Given /^the issue "([^\"]+)" has (\d+) [Cc]ost(?: )?[Ee]ntr(?:ies|y) with the following:$/ do |issue, count, table|
  i = Issue.find(:last, :conditions => ["subject = '#{issue}'"])
  as_admin count do
    ce = Factory.build(:cost_entry, :spent_on => (table.rows_hash["date"] ? table.rows_hash["date"].to_date : Date.today),
                                    :units => table.rows_hash["units"],
                                    :project => i.project,
                                    :issue => i,
                                    :user => User.find_by_login(table.rows_hash["user"]),
                                    :comments => "lorem")

    ce.cost_type = CostType.find_by_name(table.rows_hash["cost type"]) if table.rows_hash["cost type"]

    ce.save!
  end
end

Given /^there is a standard cost control project named "([^\"]*)"$/ do |name|
  steps %Q{
    Given there is 1 project with the following:
      | Name | #{name} |
    And the project "#{name}" has 1 subproject
    And the project "#{name}" has 1 issue with:
      | subject | #{name}issue |
    And the role "Manager" may have the following rights:
      | view_own_hourly_rate |
      | view_issues |
      | view_own_time_entries |
      | view_own_cost_entries |
      | view_cost_rates |
    And there is a role "Controller"
    And the role "Controller" may have the following rights:
      | View own cost entries |
    And the role "Developer" may have the following rights:
      | View own cost entries |
    And the role "Reporter" may have the following rights:
      | Create issues |
    And there is a role "Supplier"
    And the role "Supplier" may have the following rights:
      | View own hourly rate |
      | View own cost entries |
    And there is 1 user with:
      | Login | manager |
		And the user "manager" is a "Manager" in the project "#{name}"
		And there is 1 user with:
      | Login | controller |
		And the user "controller" is a "Controller" in the project "#{name}"
		And there is 1 user with:
      | Login | developer |
		And the user "developer" is a "Developer" in the project "#{name}"
		And there is 1 user with:
      | Login | reporter |
		And the user "reporter" is a "Reporter" in the project "#{name}"
  }
end

Given /^users have times and the cost type "([^\"]*)" logged on the issue "([^\"]*)" with:$/ do |cost_type, issue, table|
  i = Issue.find(:last, :conditions => ["subject = '#{issue}'"])
  raise "No such issue: #{issue}" unless i

  table.rows_hash.collect do |k,v|
    user = k.split.first
    if k.end_with? "hours"
      steps %Q{
        And the issue "#{issue}" has 1 time entry with the following:
          | hours     | #{v}    |
          | user      | #{user} |
      }
    elsif k.end_with? "units"
      steps %Q{
        And the issue "#{issue}" has 1 cost entry with the following:
        | units     | #{v}         |
        | user      | #{user}      |
        | cost type | #{cost_type} |
      }
    elsif k.end_with? "rate"
      steps %Q{
        And the user "#{user}" has:
          | default rate | #{v} |
      }
    else
      "Don't know what to do with #{k} => #{v}. Use | <username> (hours|rate|units) | <x> | as."
      next
    end
  end
end

Given /^there is a variable cost object with the following:$/ do |table|
  cost_object = Factory.build(:variable_cost_object)

  table_hash = table.rows_hash

  cost_object.created_on = table_hash.has_key?("created_on") ?
                             eval(table_hash["created_on"]) :
                             Time.now
  cost_object.fixed_date = cost_object.created_on.to_date
  cost_object.project = (Project.find_by_identifier(table_hash["project"]) || Project.find_by_name(table_hash ["project"])) if table_hash.has_key? "project"
  cost_object.author = User.current
  cost_object.subject = table_hash["subject"] if table_hash.has_key? "subject"

  cost_object.save!
  cost_object.journals.first.update_attribute(:created_at, eval(table_hash["created_on"])) if table_hash.has_key?("created_on")
end

Given /^I update the variable cost object "([^"]*)" with the following:$/ do |subject, table|
  cost_object = VariableCostObject.find_by_subject(subject)

  cost_object.subject = table.rows_hash["subject"]
  cost_object.save!
end


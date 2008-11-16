require File.dirname(__FILE__) + '/spec_helper.rb'

include RR

describe LoggedChange do
  before(:each) do
    Initializer.configuration = standard_config
  end

  it "initialize should store session and database" do
    session = Session.new
    change = LoggedChange.new session, :left
    change.session.should == session
    change.database.should == :left
  end

  it "loaded? should return true if a change was loaded" do
    change = LoggedChange.new Session.new, :left
    change.should_not be_loaded
    change.loaded = true
    change.should be_loaded
  end

  it "load_specified should load the specified change" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'wrong_table',
        'change_key' => 'id|2',
        'change_new_key' => 'id|2',
        'change_type' => 'U',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|2',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'dummy_table', 'id|2'

      change.should be_loaded
      change.table.should == 'dummy_table'
      change.type.should == :insert
      change.key.should == {'id' => '2'}
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "load_specified should accept a string as key" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'scanner_records',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'scanner_records', 'id|1'

      change.should be_loaded
      change.table.should == 'scanner_records'
      change.type.should == :insert
      change.key.should == {'id' => '1'}
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "load_specified should accept a column_name => value hash as key" do
    config = deep_copy(standard_config)
    config.included_table_specs.clear
    config.include_tables "scanner_records", :primary_key_names => ['id1', 'id2']

    session = Session.new config
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'scanner_records',
        'change_key' => 'id1|1|id2|2',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'scanner_records', {'id1' => 1, 'id2' => 2}

      change.should be_loaded
      change.table.should == 'scanner_records'
      change.type.should == :insert
      change.key.should == {'id1' => '1', 'id2' => '2'}
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "load_specified should delete loaded changes from the database" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'dummy_table', 'id|1'

      change.should be_loaded
      session.left.
        select_one("select * from rr_change_log where change_key = 'id|1'").
        should be_nil
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "load_specified should set first_change_at and last_changed_at correctly" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      t1 = 5.seconds.ago
      t2 = 5.seconds.from_now
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => t1
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_new_key' => 'id|1',
        'change_type' => 'U',
        'change_time' => t2
      }
      change = LoggedChange.new session, :left
      change.load_specified 'dummy_table', 'id|1'

      change.should be_loaded
      change.first_changed_at.to_s.should == t1.to_s
      change.last_changed_at.to_s.should == t2.to_s
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "load_specified should follow primary key updates correctly" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_new_key' => 'id|2',
        'change_type' => 'U',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|2',
        'change_new_key' => 'id|3',
        'change_type' => 'U',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'dummy_table', 'id|1'

      change.should be_loaded
      change.key.should == {'id' => '1'}
      change.new_key.should == {'id' => '3'}
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "load_specified should not load if changes cancel each other out" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_new_key' => 'id|2',
        'change_type' => 'U',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|2',
        'change_type' => 'D',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'dummy_table', 'id|1'

      change.should_not be_loaded
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "load_specified should transist states correctly" do
    session = Session.new
    session.left.begin_db_transaction
    begin

      # first test case
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'D',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_new_key' => 'id|2',
        'change_type' => 'U',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'dummy_table', 'id|1'
      change.should be_loaded
      change.type.should == :insert
      change.key.should == {'id' => '2'}

      # second test case
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|5',
        'change_type' => 'D',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|5',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'dummy_table', 'id|5'
      change.should be_loaded
      change.type.should == :update
      change.key.should == {'id' => '5'}
      change.new_key.should == {'id' => '5'}
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "amend should amend the change correctly" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'left_table', {
        :id => '1',
        :name => 'bla'
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'left_table',
        'change_key' => 'id|1',
        'change_new_key' => 'id|1',
        'change_type' => 'U',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'left_table', 'id|1'
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'left_table',
        'change_key' => 'id|1',
        'change_type' => 'D',
        'change_time' => Time.now
      }
      change.amend

      change.should be_loaded
      change.table.should == 'left_table'
      change.type.should == :delete
      change.key.should == {'id' => '1'}
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "amend should support primary key updates" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'left_table', {
        :id => '1',
        :name => 'bla'
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'left_table',
        'change_key' => 'id|1',
        'change_new_key' => 'id|2',
        'change_type' => 'U',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_specified 'left_table', 'id|1'
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'left_table',
        'change_key' => 'id|2',
        'change_new_key' => 'id|3',
        'change_type' => 'U',
        'change_time' => Time.now
      }
      change.amend

      change.should be_loaded
      change.table.should == 'left_table'
      change.type.should == :update
      change.key.should == {'id' => '1'}
      change.new_key.should == {'id' => '3'}
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "oldest_change_time should return nil if there are no changes" do
    change = LoggedChange.new Session.new, :left
    change.oldest_change_time.should be_nil
  end

  it "oldest_change_time should return the time of the oldest change" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      time = Time.now
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => time
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|2',
        'change_type' => 'I',
        'change_time' => 100.seconds.from_now
      }
      change = LoggedChange.new session, :left
      change.oldest_change_time.should.to_s == time.to_s
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "key_from_raw_key should return the correct column_name => value hash for the given key" do
    change = LoggedChange.new Session.new, :left
    change.key_to_hash("a|1|b|2").should == {
      'a' => '1',
      'b' => '2'
    }
  end

  it "load_oldest should not load a change if none available" do
    change = LoggedChange.new Session.new, :left
    change.should_not_receive :load_specified
    change.load_oldest
  end

  it "load_oldest should load the oldest available change" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|2',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_oldest

      change.should be_loaded
      change.key.should == {'id' => '1'}
    ensure
      session.left.rollback_db_transaction
    end
  end

  it "load_oldest should skip irrelevant changes" do
    session = Session.new
    session.left.begin_db_transaction
    begin
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|1',
        'change_type' => 'D',
        'change_time' => Time.now
      }
      session.left.insert_record 'rr_change_log', {
        'change_table' => 'dummy_table',
        'change_key' => 'id|2',
        'change_type' => 'I',
        'change_time' => Time.now
      }
      change = LoggedChange.new session, :left
      change.load_oldest

      change.should be_loaded
      change.key.should == {'id' => '2'}
    ensure
      session.left.rollback_db_transaction
    end
  end
end

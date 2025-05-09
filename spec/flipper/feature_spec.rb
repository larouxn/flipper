require 'flipper/feature'
require 'flipper/instrumenters/memory'

RSpec.describe Flipper::Feature do
  subject { described_class.new(:search, adapter) }

  let(:adapter) { Flipper::Adapters::Memory.new }

  describe '#initialize' do
    it 'sets name' do
      feature = described_class.new(:search, adapter)
      expect(feature.name).to eq(:search)
    end

    it 'sets adapter' do
      feature = described_class.new(:search, adapter)
      expect(feature.adapter).to eq(adapter)
    end

    it 'defaults instrumenter' do
      feature = described_class.new(:search, adapter)
      expect(feature.instrumenter).to be(Flipper::Instrumenters::Noop)
    end

    context 'with overriden instrumenter' do
      let(:instrumenter) { double('Instrumentor', instrument: nil) }

      it 'overrides default instrumenter' do
        feature = described_class.new(:search, adapter, instrumenter: instrumenter)
        expect(feature.instrumenter).to be(instrumenter)
      end
    end
  end

  describe "#enabled?" do
    context "for an actor" do
      let(:actor) { Flipper::Actor.new("User;1") }

      it 'returns true if feature is enabled' do
        subject.enable
        expect(subject.enabled?(actor)).to be(true)
      end

      it 'returns false if feature is disabled' do
        subject.disable
        expect(subject.enabled?(actor)).to be(false)
      end
    end

    context "for multiple actors" do
      let(:actors) {
        [
          Flipper::Actor.new("User;1"),
          Flipper::Actor.new("User;2"),
          Flipper::Actor.new("User;3"),
        ]
      }

      it 'returns true if feature is enabled' do
        subject.enable
        expect(subject.enabled?(actors)).to be(true)
      end

      it 'returns true if feature is enabled for any actor' do
        subject.enable_actor actors.first
        expect(subject.enabled?(actors)).to be(true)
      end

      it 'returns true if feature is enabled for any actor with multiple arguments' do
        subject.enable_actor actors.last
        expect(subject.enabled?(*actors)).to be(true)
      end

      it 'returns false if feature is disabled for all actors' do
        subject.disable
        expect(subject.enabled?(actors)).to be(false)
      end
    end

    context "for an object that implements .nil? == true" do
      let(:actor) { Flipper::Actor.new("User;1") }

      before do
        def actor.nil?
          true
        end
      end

      it 'returns true if feature is enabled' do
        subject.enable
        expect(subject.enabled?(actor)).to be(true)
      end

      it 'returns false if feature is disabled' do
        subject.disable
        expect(subject.enabled?(actor)).to be(false)
      end
    end
  end

  describe '#to_s' do
    it 'returns name as string' do
      feature = described_class.new(:search, adapter)
      expect(feature.to_s).to eq('search')
    end
  end

  describe '#to_param' do
    it 'returns name as string' do
      feature = described_class.new(:search, adapter)
      expect(feature.to_param).to eq('search')
    end
  end

  describe '#gate_for' do
    context 'with percentage of actors' do
      it 'returns percentage of actors gate' do
        percentage = Flipper::Types::PercentageOfActors.new(10)
        gate = subject.gate_for(percentage)
        expect(gate).to be_instance_of(Flipper::Gates::PercentageOfActors)
      end
    end
  end

  describe '#gates' do
    it 'returns array of gates' do
      instance = described_class.new(:search, adapter)
      expect(instance.gates).to be_instance_of(Array)
      instance.gates.each do |gate|
        expect(gate).to be_a(Flipper::Gate)
      end
      expect(instance.gates.size).to be(6)
    end
  end

  describe '#gate' do
    context 'with symbol name' do
      it 'returns gate by name' do
        expect(subject.gate(:boolean)).to be_instance_of(Flipper::Gates::Boolean)
      end
    end

    context 'with string name' do
      it 'returns gate by name' do
        expect(subject.gate('boolean')).to be_instance_of(Flipper::Gates::Boolean)
      end
    end

    context 'with name that does not exist' do
      it 'returns nil' do
        expect(subject.gate(:poo)).to be_nil
      end
    end
  end

  describe '#add' do
    it 'adds feature to adapter' do
      expect(adapter.features).to eq(Set.new)
      subject.add
      expect(adapter.features).to eq(Set[subject.key])
    end
  end

  describe '#exist?' do
    it 'returns true if feature is added in adapter' do
      subject.add
      expect(subject.exist?).to be(true)
    end

    it 'returns false if feature is NOT added in adapter' do
      expect(subject.exist?).to be(false)
    end
  end

  describe '#remove' do
    it 'removes feature from adapter' do
      adapter.add(subject)
      expect(adapter.features).to eq(Set[subject.key])
      subject.remove
      expect(adapter.features).to eq(Set.new)
    end
  end

  describe '#clear' do
    it 'clears feature using adapter' do
      subject.enable
      expect(subject).to be_enabled
      subject.clear
      expect(subject).not_to be_enabled
    end
  end

  describe '#inspect' do
    it 'returns easy to read string representation' do
      string = subject.inspect
      expect(string).to include('Flipper::Feature')
      expect(string).to include('name=:search')
      expect(string).to include('state=:off')
      expect(string).to include('enabled_gate_names=[]')
      expect(string).to include("adapter=#{subject.adapter.name.inspect}")

      subject.enable
      string = subject.inspect
      expect(string).to include('state=:on')
      expect(string).to include('enabled_gate_names=[:boolean]')
    end
  end

  describe 'instrumentation' do
    let(:instrumenter) { Flipper::Instrumenters::Memory.new }

    subject do
      described_class.new(:search, adapter, instrumenter: instrumenter)
    end

    it 'is recorded for enable' do
      actor = Flipper::Types::Actor.new(Flipper::Actor.new('1'))
      subject.gate_for(actor)

      subject.enable(actor)

      event = instrumenter.events.last
      expect(event).not_to be_nil
      expect(event.name).to eq('feature_operation.flipper')
      expect(event.payload[:feature_name]).to eq(:search)
      expect(event.payload[:operation]).to eq(:enable)
      expect(event.payload[:thing]).to eq(actor)
      expect(event.payload[:result]).not_to be_nil
    end

    it 'always instruments flipper type instance for enable' do
      actor = Flipper::Actor.new('1')
      subject.gate_for(actor)

      subject.enable(actor)

      event = instrumenter.events.last
      expect(event).not_to be_nil
      expect(event.payload[:thing]).to eq(Flipper::Types::Actor.new(actor))
    end

    it 'is recorded for disable' do
      thing = Flipper::Types::Boolean.new

      subject.disable(thing)

      event = instrumenter.events.last
      expect(event).not_to be_nil
      expect(event.name).to eq('feature_operation.flipper')
      expect(event.payload[:feature_name]).to eq(:search)
      expect(event.payload[:operation]).to eq(:disable)
      expect(event.payload[:thing]).to eq(thing)
      expect(event.payload[:result]).not_to be_nil
    end

    user = Flipper::Actor.new('1')
    actor = Flipper::Types::Actor.new(user)
    boolean_true = Flipper::Types::Boolean.new(true)
    boolean_false = Flipper::Types::Boolean.new(false)
    group = Flipper::Types::Group.new(:admins)
    percentage_of_time = Flipper::Types::PercentageOfTime.new(10)
    percentage_of_actors = Flipper::Types::PercentageOfActors.new(10)
    {
      user => actor,
      actor => actor,
      true => boolean_true,
      false => boolean_false,
      boolean_true => boolean_true,
      boolean_false => boolean_false,
      :admins => group,
      group => group,
      percentage_of_time => percentage_of_time,
      percentage_of_actors => percentage_of_actors,
    }.each do |thing, wrapped_thing|
      it "always instruments #{thing.inspect} as #{wrapped_thing.class} for enable" do
        Flipper.register(:admins) {}
        subject.enable(thing)

        event = instrumenter.events.last
        expect(event).not_to be_nil
        expect(event.payload[:operation]).to eq(:enable)
        expect(event.payload[:thing]).to eq(wrapped_thing)
      end
    end

    it 'always instruments flipper type instance for disable' do
      actor = Flipper::Actor.new('1')

      subject.disable(actor)

      event = instrumenter.events.last
      expect(event).not_to be_nil
      expect(event.payload[:operation]).to eq(:disable)
      expect(event.payload[:thing]).to eq(Flipper::Types::Actor.new(actor))
    end

    it 'is recorded for add' do
      subject.add

      event = instrumenter.events.last
      expect(event).not_to be_nil
      expect(event.name).to eq('feature_operation.flipper')
      expect(event.payload[:feature_name]).to eq(:search)
      expect(event.payload[:operation]).to eq(:add)
      expect(event.payload[:result]).not_to be_nil
    end

    it 'is recorded for exist?' do
      subject.exist?

      event = instrumenter.events.last
      expect(event).not_to be_nil
      expect(event.name).to eq('feature_operation.flipper')
      expect(event.payload[:feature_name]).to eq(:search)
      expect(event.payload[:operation]).to eq(:exist?)
      expect(event.payload[:result]).not_to be_nil
    end

    it 'is recorded for remove' do
      subject.remove

      event = instrumenter.events.last
      expect(event).not_to be_nil
      expect(event.name).to eq('feature_operation.flipper')
      expect(event.payload[:feature_name]).to eq(:search)
      expect(event.payload[:operation]).to eq(:remove)
      expect(event.payload[:result]).not_to be_nil
    end

    it 'is recorded for clear' do
      subject.clear

      event = instrumenter.events.last
      expect(event).not_to be_nil
      expect(event.name).to eq('feature_operation.flipper')
      expect(event.payload[:feature_name]).to eq(:search)
      expect(event.payload[:operation]).to eq(:clear)
      expect(event.payload[:result]).not_to be_nil
    end

    it 'is recorded for enabled?' do
      actor = Flipper::Types::Actor.new(Flipper::Actor.new('1'))
      subject.enabled?(actor)

      event = instrumenter.events.last
      expect(event).not_to be_nil
      expect(event.name).to eq('feature_operation.flipper')
      expect(event.payload[:feature_name]).to eq(:search)
      expect(event.payload[:operation]).to eq(:enabled?)
      expect(event.payload[:actors]).to eq([actor])
      expect(event.payload[:result]).to eq(false)
    end

    user = Flipper::Actor.new('1')
    actor = Flipper::Types::Actor.new(user)
    {
      nil => nil,
      user => [actor],
      actor => [actor],
    }.each do |thing, wrapped_thing|
      it "always instruments #{thing.inspect} as #{wrapped_thing.class} for enabled?" do
        subject.enabled?(thing)

        event = instrumenter.events.last
        expect(event).not_to be_nil
        expect(event.payload[:operation]).to eq(:enabled?)
        expect(event.payload[:actors]).to eq(wrapped_thing)
      end
    end
  end

  describe '#state' do
    context 'fully on' do
      before do
        subject.enable
      end

      it 'returns :on' do
        expect(subject.state).to be(:on)
      end

      it 'returns true for on?' do
        expect(subject.on?).to be(true)
      end

      it 'returns false for off?' do
        expect(subject.off?).to be(false)
      end

      it 'returns false for conditional?' do
        expect(subject.conditional?).to be(false)
      end
    end

    context 'percentage of time set to 100' do
      before do
        subject.enable_percentage_of_time 100
      end

      it 'returns :on' do
        expect(subject.state).to be(:on)
      end

      it 'returns true for on?' do
        expect(subject.on?).to be(true)
      end

      it 'returns false for off?' do
        expect(subject.off?).to be(false)
      end

      it 'returns false for conditional?' do
        expect(subject.conditional?).to be(false)
      end
    end

    context 'percentage of actors set to 100' do
      before do
        subject.enable_percentage_of_actors 100
      end

      it 'returns :on' do
        expect(subject.state).to be(:conditional)
      end

      it 'returns false for on?' do
        expect(subject.on?).to be(false)
      end

      it 'returns false for off?' do
        expect(subject.off?).to be(false)
      end

      it 'returns true for conditional?' do
        expect(subject.conditional?).to be(true)
      end
    end

    context 'fully off' do
      before do
        subject.disable
      end

      it 'returns :off' do
        expect(subject.state).to be(:off)
      end

      it 'returns false for on?' do
        expect(subject.on?).to be(false)
      end

      it 'returns true for off?' do
        expect(subject.off?).to be(true)
      end

      it 'returns false for conditional?' do
        expect(subject.conditional?).to be(false)
      end
    end

    context 'partially on' do
      before do
        subject.enable Flipper::Types::PercentageOfTime.new(5)
      end

      it 'returns :conditional' do
        expect(subject.state).to be(:conditional)
      end

      it 'returns false for on?' do
        expect(subject.on?).to be(false)
      end

      it 'returns false for off?' do
        expect(subject.off?).to be(false)
      end

      it 'returns true for conditional?' do
        expect(subject.conditional?).to be(true)
      end
    end
  end

  describe '#enabled_groups' do
    context 'when no groups enabled' do
      it 'returns empty set' do
        expect(subject.enabled_groups).to eq(Set.new)
      end
    end

    context 'when one or more groups enabled' do
      before do
        @staff = Flipper.register(:staff) { |actor| true }
        @preview_features = Flipper.register(:preview_features) { |actor| true }
        @not_enabled = Flipper.register(:not_enabled) { |actor| true }
        @disabled = Flipper.register(:disabled) { |actor| true }
        subject.enable @staff
        subject.enable @preview_features
        subject.disable @disabled
      end

      it 'returns set of enabled groups' do
        expect(subject.enabled_groups).to eq(Set.new([
                                                       @staff,
                                                       @preview_features,
                                                     ]))
      end

      it 'does not include groups that have not been enabled' do
        expect(subject.enabled_groups).not_to include(@not_enabled)
      end

      it 'does not include disabled groups' do
        expect(subject.enabled_groups).not_to include(@disabled)
      end

      it 'is aliased to groups' do
        expect(subject.enabled_groups).to eq(subject.groups)
      end
    end
  end

  describe '#disabled_groups' do
    context 'when no groups enabled' do
      it 'returns empty set' do
        expect(subject.disabled_groups).to eq(Set.new)
      end
    end

    context 'when one or more groups enabled' do
      before do
        @staff = Flipper.register(:staff) { |actor| true }
        @preview_features = Flipper.register(:preview_features) { |actor| true }
        @not_enabled = Flipper.register(:not_enabled) { |actor| true }
        @disabled = Flipper.register(:disabled) { |actor| true }
        subject.enable @staff
        subject.enable @preview_features
        subject.disable @disabled
      end

      it 'returns set of groups that are not enabled' do
        expect(subject.disabled_groups).to eq(Set[
                  @not_enabled,
                  @disabled,
                ])
      end
    end
  end

  describe '#groups_value' do
    context 'when no groups enabled' do
      it 'returns empty set' do
        expect(subject.groups_value).to eq(Set.new)
      end
    end

    context 'when one or more groups enabled' do
      before do
        @staff = Flipper.register(:staff) { |actor| true }
        @preview_features = Flipper.register(:preview_features) { |actor| true }
        @not_enabled = Flipper.register(:not_enabled) { |actor| true }
        @disabled = Flipper.register(:disabled) { |actor| true }
        subject.enable @staff
        subject.enable @preview_features
        subject.disable @disabled
      end

      it 'returns set of enabled groups' do
        expect(subject.groups_value).to eq(Set.new([
                                                     @staff.name.to_s,
                                                     @preview_features.name.to_s,
                                                   ]))
      end

      it 'does not include groups that have not been enabled' do
        expect(subject.groups_value).not_to include(@not_enabled.name.to_s)
      end

      it 'does not include disabled groups' do
        expect(subject.groups_value).not_to include(@disabled.name.to_s)
      end
    end
  end

  describe '#actors_value' do
    context 'when no groups enabled' do
      it 'returns empty set' do
        expect(subject.actors_value).to eq(Set.new)
      end
    end

    context 'when one or more actors are enabled' do
      before do
        subject.enable Flipper::Types::Actor.new(Flipper::Actor.new('User;5'))
        subject.enable Flipper::Types::Actor.new(Flipper::Actor.new('User;22'))
      end

      it 'returns set of actor ids' do
        expect(subject.actors_value).to eq(Set.new(['User;5', 'User;22']))
      end
    end
  end

  describe '#boolean_value' do
    context 'when not enabled or disabled' do
      it 'returns false' do
        expect(subject.boolean_value).to be(false)
      end
    end

    context 'when enabled' do
      before do
        subject.enable
      end

      it 'returns true' do
        expect(subject.boolean_value).to be(true)
      end
    end

    context 'when disabled' do
      before do
        subject.disable
      end

      it 'returns false' do
        expect(subject.boolean_value).to be(false)
      end
    end
  end

  describe '#percentage_of_actors_value' do
    context 'when not enabled or disabled' do
      it 'returns nil' do
        expect(subject.percentage_of_actors_value).to be(0)
      end
    end

    context 'when enabled' do
      before do
        subject.enable Flipper::Types::PercentageOfActors.new(5)
      end

      it 'returns true' do
        expect(subject.percentage_of_actors_value).to eq(5)
      end
    end

    context 'when disabled' do
      before do
        subject.disable
      end

      it 'returns nil' do
        expect(subject.percentage_of_actors_value).to be(0)
      end
    end
  end

  describe '#percentage_of_time_value' do
    context 'when not enabled or disabled' do
      it 'returns nil' do
        expect(subject.percentage_of_time_value).to be(0)
      end
    end

    context 'when enabled' do
      before do
        subject.enable Flipper::Types::PercentageOfTime.new(5)
      end

      it 'returns true' do
        expect(subject.percentage_of_time_value).to eq(5)
      end
    end

    context 'when disabled' do
      before do
        subject.disable
      end

      it 'returns nil' do
        expect(subject.percentage_of_time_value).to be(0)
      end
    end
  end

  describe '#gate_values' do
    context 'when no gates are set in adapter' do
      it 'returns default gate values' do
        expect(subject.gate_values).to eq(Flipper::GateValues.new(adapter.default_config))
      end
    end

    context 'with gate values set in adapter' do
      before do
        subject.enable Flipper::Types::Boolean.new(true)
        subject.enable Flipper::Types::Actor.new(Flipper::Actor.new(5))
        subject.enable Flipper::Types::Group.new(:admins)
        subject.enable Flipper::Types::PercentageOfTime.new(50)
        subject.enable Flipper::Types::PercentageOfActors.new(25)
      end

      it 'returns gate values' do
        expect(subject.gate_values).to eq(Flipper::GateValues.new(actors: Set.new(['5']),
                                                                  groups: Set.new(['admins']),
                                                                  boolean: 'true',
                                                                  percentage_of_time: '50',
                                                                  percentage_of_actors: '25'))
      end
    end
  end

  describe '#expression' do
    it "returns nil if feature has no expression" do
      expect(subject.expression).to be(nil)
    end

    it "returns expression if feature has expression" do
      expression = Flipper.property(:plan).eq("basic")
      subject.enable_expression expression
      expect(subject.expression).to eq(expression)
    end
  end

  describe '#enable_expression/disable_expression' do
    context "with expression instance" do
      it "updates gate values to equal expression or clears expression" do
        expression = Flipper.property(:plan).eq("basic")
        expect(subject.gate_values.expression).to be(nil)
        subject.enable_expression(expression)
        expect(subject.gate_values.expression).to eq(expression.value)
        subject.disable_expression
        expect(subject.gate_values.expression).to be(nil)
      end
    end

    context "with Hash" do
      it "updates gate values to equal expression or clears expression" do
        expression = Flipper.property(:plan).eq("basic")
        expect(subject.gate_values.expression).to be(nil)
        subject.enable_expression(expression.value)
        expect(subject.gate_values.expression).to eq(expression.value)
        subject.disable_expression
        expect(subject.gate_values.expression).to be(nil)
      end
    end
  end

  describe "#add_expression" do
    context "when nothing enabled" do
      context "with Expression instance" do
        it "sets expression to Expression" do
          expression = Flipper.property(:plan).eq("basic")
          subject.add_expression(expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression).to eq(expression)
        end
      end

      context "with Any instance" do
        it "sets expression to Any" do
          expression = Flipper.any(Flipper.property(:plan).eq("basic"))
          subject.add_expression(expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression).to eq(expression)
        end
      end

      context "with All instance" do
        it "sets expression to All" do
          expression = Flipper.all(Flipper.property(:plan).eq("basic"))
          subject.add_expression(expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression).to eq(expression)
        end
      end
    end

    context "when Expression enabled" do
      let(:expression) { Flipper.property(:plan).eq("basic") }

      before do
        subject.enable_expression expression
      end

      context "with Expression instance" do
        it "changes expression to Any and adds new Expression" do
          new_expression = Flipper.property(:age).gte(21)
          subject.add_expression(new_expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression.args).to include(expression)
          expect(subject.expression.args).to include(new_expression)
        end
      end

      context "with Any instance" do
        it "changes expression to Any and adds new Any" do
          new_expression = Flipper.any(Flipper.property(:age).eq(21))
          subject.add_expression new_expression
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression.args).to include(expression)
          expect(subject.expression.args).to include(new_expression)
        end
      end

      context "with All instance" do
        it "changes expression to Any and adds new All" do
          new_expression = Flipper.all(Flipper.property(:plan).eq("basic"))
          subject.add_expression new_expression
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression.args).to include(expression)
          expect(subject.expression.args).to include(new_expression)
        end
      end
    end

    context "when Any enabled" do
      let(:condition) { Flipper.property(:plan).eq("basic") }
      let(:expression) { Flipper.any(condition) }

      before do
        subject.enable_expression expression
      end

      context "with Expression instance" do
        it "adds Expression to Any" do
          new_expression = Flipper.property(:age).gte(21)
          subject.add_expression(new_expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression.args).to include(condition)
          expect(subject.expression.args).to include(new_expression)
        end
      end

      context "with Any instance" do
        it "adds Any to Any" do
          new_expression = Flipper.any(Flipper.property(:age).gte(21))
          subject.add_expression(new_expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression.args).to include(condition)
          expect(subject.expression.args).to include(new_expression)
        end
      end

      context "with All instance" do
        it "adds All to Any" do
          new_expression = Flipper.all(Flipper.property(:age).gte(21))
          subject.add_expression(new_expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression.args).to include(condition)
          expect(subject.expression.args).to include(new_expression)
        end
      end
    end

    context "when All enabled" do
      let(:condition) { Flipper.property(:plan).eq("basic") }
      let(:expression) { Flipper.all(condition) }

      before do
        subject.enable_expression expression
      end

      context "with Expression instance" do
        it "adds Expression to All" do
          new_expression = Flipper.property(:age).gte(21)
          subject.add_expression(new_expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression.args).to include(condition)
          expect(subject.expression.args).to include(new_expression)
        end
      end

      context "with Any instance" do
        it "adds Any to All" do
          new_expression = Flipper.any(Flipper.property(:age).gte(21))
          subject.add_expression(new_expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression.args).to include(condition)
          expect(subject.expression.args).to include(new_expression)
        end
      end

      context "with All instance" do
        it "adds All to All" do
          new_expression = Flipper.all(Flipper.property(:age).gte(21))
          subject.add_expression(new_expression)
          expect(subject.expression).to be_instance_of(Flipper::Expression)
          expect(subject.expression.args).to include(condition)
          expect(subject.expression.args).to include(new_expression)
        end
      end
    end
  end

  describe '#remove_expression' do
    context "when nothing enabled" do
      context "with Expression instance" do
        it "does nothing" do
          expression = Flipper.property(:plan).eq("basic")
          subject.remove_expression(expression)
          expect(subject.expression).to be(nil)
        end
      end

      context "with Any instance" do
        it "does nothing" do
          expression = Flipper.any(Flipper.property(:plan).eq("basic"))
          subject.remove_expression expression
          expect(subject.expression).to be(nil)
        end
      end

      context "with All instance" do
        it "does nothing" do
          expression = Flipper.all(Flipper.property(:plan).eq("basic"))
          subject.remove_expression expression
          expect(subject.expression).to be(nil)
        end
      end
    end

    context "when Expression enabled" do
      let(:expression) { Flipper.property(:plan).eq("basic") }

      before do
        subject.enable_expression expression
      end

      context "with Expression instance" do
        it "changes expression to Any and removes Expression if it matches" do
          new_expression = Flipper.property(:plan).eq("basic")
          subject.remove_expression new_expression
          expect(subject.expression).to eq(Flipper.any)
        end

        it "changes expression to Any if Expression doesn't match" do
          new_expression = Flipper.property(:plan).eq("premium")
          subject.remove_expression new_expression
          expect(subject.expression).to eq(Flipper.any(expression))
        end
      end

      context "with Any instance" do
        it "changes expression to Any and does nothing" do
          new_expression = Flipper.any(Flipper.property(:plan).eq("basic"))
          subject.remove_expression new_expression
          expect(subject.expression).to eq(Flipper.any(expression))
        end
      end

      context "with All instance" do
        it "changes expression to Any and does nothing" do
          new_expression = Flipper.all(Flipper.property(:plan).eq("basic"))
          subject.remove_expression new_expression
          expect(subject.expression).to eq(Flipper.any(expression))
        end
      end
    end

    context "when Any enabled" do
      let(:condition) { Flipper.property(:plan).eq("basic") }
      let(:expression) { Flipper.any condition }

      before do
        subject.enable_expression expression
      end

      context "with Expression instance" do
        it "removes Expression if it matches" do
          subject.remove_expression condition
          expect(subject.expression).to eq(Flipper.any)
        end

        it "does nothing if Expression does not match" do
          subject.remove_expression Flipper.property(:plan).eq("premium")
          expect(subject.expression).to eq(expression)
        end
      end

      context "with Any instance" do
        it "removes Any if it matches" do
          new_expression = Flipper.any(Flipper.property(:plan).eq("premium"))
          subject.add_expression new_expression
          expect(subject.expression.args.size).to be(2)
          subject.remove_expression new_expression
          expect(subject.expression).to eq(expression)
        end

        it "does nothing if Any does not match" do
          new_expression = Flipper.any(Flipper.property(:plan).eq("premium"))
          subject.remove_expression new_expression
          expect(subject.expression).to eq(expression)
        end
      end

      context "with All instance" do
        it "removes All if it matches" do
          new_expression = Flipper.all(Flipper.property(:plan).eq("premium"))
          subject.add_expression new_expression
          expect(subject.expression.args.size).to be(2)
          subject.remove_expression new_expression
          expect(subject.expression).to eq(expression)
        end

        it "does nothing if All does not match" do
          new_expression = Flipper.all(Flipper.property(:plan).eq("premium"))
          subject.remove_expression new_expression
          expect(subject.expression).to eq(expression)
        end
      end
    end

    context "when All enabled" do
      let(:condition) { Flipper.property(:plan).eq("basic") }
      let(:expression) { Flipper.all condition }

      before do
        subject.enable_expression expression
      end

      context "with Expression instance" do
        it "removes Expression if it matches" do
          subject.remove_expression condition
          expect(subject.expression).to eq(Flipper.all)
        end

        it "does nothing if Expression does not match" do
          subject.remove_expression Flipper.property(:plan).eq("premium")
          expect(subject.expression).to eq(expression)
        end
      end

      context "with Any instance" do
        it "removes Any if it matches" do
          new_expression = Flipper.any(Flipper.property(:plan).eq("premium"))
          subject.add_expression new_expression
          expect(subject.expression.args.size).to be(2)
          subject.remove_expression new_expression
          expect(subject.expression).to eq(expression)
        end

        it "does nothing if Any does not match" do
          new_expression = Flipper.any(Flipper.property(:plan).eq("premium"))
          subject.remove_expression new_expression
          expect(subject.expression).to eq(expression)
        end
      end

      context "with All instance" do
        it "removes All if it matches" do
          new_expression = Flipper.all(Flipper.property(:plan).eq("premium"))
          subject.add_expression new_expression
          expect(subject.expression.args.size).to be(2)
          subject.remove_expression new_expression
          expect(subject.expression).to eq(expression)
        end

        it "does nothing if All does not match" do
          new_expression = Flipper.all(Flipper.property(:plan).eq("premium"))
          subject.remove_expression new_expression
          expect(subject.expression).to eq(expression)
        end
      end
    end
  end

  describe '#enable_actor/disable_actor' do
    context 'with object that responds to flipper_id' do
      it 'updates the gate values to include the actor' do
        actor = Flipper::Actor.new(5)
        expect(subject.gate_values.actors).to be_empty
        subject.enable_actor(actor)
        expect(subject.gate_values.actors).to eq(Set['5'])
        subject.disable_actor(actor)
        expect(subject.gate_values.actors).to be_empty
      end
    end

    context 'with actor instance' do
      it 'updates the gate values to include the actor' do
        actor = Flipper::Actor.new(5)
        instance = Flipper::Types::Actor.new(actor)
        expect(subject.gate_values.actors).to be_empty
        subject.enable_actor(instance)
        expect(subject.gate_values.actors).to eq(Set['5'])
        subject.disable_actor(instance)
        expect(subject.gate_values.actors).to be_empty
      end
    end
  end

  describe '#enable_group/disable_group' do
    context 'with symbol group name' do
      it 'updates the gate values to include the group' do
        expect(subject.gate_values.groups).to be_empty
        subject.enable_group(:five_only)
        expect(subject.gate_values.groups).to eq(Set['five_only'])
        subject.disable_group(:five_only)
        expect(subject.gate_values.groups).to be_empty
      end
    end

    context 'with string group name' do
      it 'updates the gate values to include the group' do
        expect(subject.gate_values.groups).to be_empty
        subject.enable_group('five_only')
        expect(subject.gate_values.groups).to eq(Set['five_only'])
        subject.disable_group('five_only')
        expect(subject.gate_values.groups).to be_empty
      end
    end

    context 'with group instance' do
      it 'updates the gate values for the group' do
        group = Flipper.register(:five_only) { |actor| actor.flipper_id == 5 }
        expect(subject.gate_values.groups).to be_empty
        subject.enable_group(group)
        expect(subject.gate_values.groups).to eq(Set['five_only'])
        subject.disable_group(group)
        expect(subject.gate_values.groups).to be_empty
      end
    end
  end

  describe '#enable_percentage_of_time/disable_percentage_of_time' do
    context 'with integer' do
      it 'updates the gate values' do
        expect(subject.gate_values.percentage_of_time).to be(0)
        subject.enable_percentage_of_time(56)
        expect(subject.gate_values.percentage_of_time).to be(56)
        subject.disable_percentage_of_time
        expect(subject.gate_values.percentage_of_time).to be(0)
      end
    end

    context 'with string' do
      it 'updates the gate values' do
        expect(subject.gate_values.percentage_of_time).to be(0)
        subject.enable_percentage_of_time('56')
        expect(subject.gate_values.percentage_of_time).to be(56)
        subject.disable_percentage_of_time
        expect(subject.gate_values.percentage_of_time).to be(0)
      end
    end

    context 'with percentage of time instance' do
      it 'updates the gate values' do
        percentage = Flipper::Types::PercentageOfTime.new(56)
        expect(subject.gate_values.percentage_of_time).to be(0)
        subject.enable_percentage_of_time(percentage)
        expect(subject.gate_values.percentage_of_time).to be(56)
        subject.disable_percentage_of_time
        expect(subject.gate_values.percentage_of_time).to be(0)
      end
    end
  end

  describe '#enable_percentage_of_actors/disable_percentage_of_actors' do
    context 'with integer' do
      it 'updates the gate values' do
        expect(subject.gate_values.percentage_of_actors).to be(0)
        subject.enable_percentage_of_actors(56)
        expect(subject.gate_values.percentage_of_actors).to be(56)
        subject.disable_percentage_of_actors
        expect(subject.gate_values.percentage_of_actors).to be(0)
      end
    end

    context 'with string' do
      it 'updates the gate values' do
        expect(subject.gate_values.percentage_of_actors).to be(0)
        subject.enable_percentage_of_actors('56')
        expect(subject.gate_values.percentage_of_actors).to be(56)
        subject.disable_percentage_of_actors
        expect(subject.gate_values.percentage_of_actors).to be(0)
      end
    end

    context 'with percentage of actors instance' do
      it 'updates the gate values' do
        percentage = Flipper::Types::PercentageOfActors.new(56)
        expect(subject.gate_values.percentage_of_actors).to be(0)
        subject.enable_percentage_of_actors(percentage)
        expect(subject.gate_values.percentage_of_actors).to be(56)
        subject.disable_percentage_of_actors
        expect(subject.gate_values.percentage_of_actors).to be(0)
      end
    end
  end

  describe '#enabled/disabled_gates' do
    before do
      subject.enable_percentage_of_time 5
      subject.enable_percentage_of_actors 5
    end

    it 'can return enabled gates' do
      expect(subject.enabled_gates.map(&:name).to_set).to eq(Set[
              :percentage_of_actors,
              :percentage_of_time,
            ])

      expect(subject.enabled_gate_names.to_set).to eq(Set[
              :percentage_of_actors,
              :percentage_of_time,
            ])
    end

    it 'can return disabled gates' do
      expect(subject.disabled_gates.map(&:name).to_set).to eq(Set[
              :actor,
              :boolean,
              :group,
              :expression,
            ])

      expect(subject.disabled_gate_names.to_set).to eq(Set[
              :actor,
              :boolean,
              :group,
              :expression,
            ])
    end
  end
end

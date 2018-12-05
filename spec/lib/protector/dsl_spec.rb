require 'spec_helpers/boot'

describe Protector::DSL do
  describe Protector::DSL::Base do
    before :each do
      @base = Class.new { include Protector::DSL::Base }
    end

    it 'defines proper methods' do
      expect(@base.instance_methods).to include(:restrict!)
      expect(@base.instance_methods).to include(:protector_subject)
    end

    it 'throws error for empty subect' do
      base = @base.new
      expect { base.protector_subject }.to raise_error(RuntimeError)
    end

    it 'accepts nil as a subject' do
      base = @base.new.restrict!(nil)
      expect { base.protector_subject }.to_not raise_error
    end

    it 'remembers protection subject' do
      base = @base.new
      base.restrict!('universe')
      expect(base.protector_subject).to eq 'universe'
    end

    it 'forgets protection subject' do
      base = @base.new
      base.restrict!('universe')
      expect(base.protector_subject).to eq 'universe'
      base.unrestrict!
      expect { base.protector_subject }.to raise_error(RuntimeError)
    end

    it 'respects `insecurely`' do
      base = @base.new
      base.restrict!('universe')

      expect(base.protector_subject?).to eq true
      Protector.insecurely do
        expect(base.protector_subject?).to eq false
      end
    end

    it 'allows nesting of `insecurely`' do
      base = @base.new
      base.restrict!('universe')

      expect(base.protector_subject?).to eq true
      Protector.insecurely do
        Protector.insecurely do
          expect(base.protector_subject?).to eq false
        end
      end
    end
  end

  describe Protector::DSL::Entry do
    before :each do
      @entry = Class.new do
        include Protector::DSL::Entry

        def self.protector_meta
          @protector_meta ||= Protector::DSL::Meta.new(nil, nil) { [] }
        end
      end
    end

    it 'instantiates meta entity' do
      @entry.instance_eval do
        protect { ; }
      end

      expect(@entry.protector_meta).to be_an_instance_of(Protector::DSL::Meta)
    end
  end

  describe Protector::DSL::Meta do
    context 'basic methods' do
      l = ->(x) { x > 4 }

      before :each do
        @meta = Protector::DSL::Meta.new(nil, nil) { %w[field1 field2 field3 field4 field5] }
        @meta << lambda {
          can :read
        }

        @meta << lambda { |user|
          scope { 'relation' } if user
        }

        @meta << lambda { |user|
          user.should == 'user' if user

          cannot :read, %w[field5], :field4
        }

        @meta << lambda { |user, entry|
          user.should  == 'user' if user
          entry.should == 'entry' if user

          can :update, %w[field1 field2],
              field3: 1,
              field4: 0..5,
              field5: l

          can :destroy
        }
      end

      it 'evaluates' do
        @meta.evaluate('user', 'entry')
      end

      context 'adequate', paranoid: false do
        it 'sets scoped?' do
          data = @meta.evaluate(nil, 'entry')
          expect(data.scoped?).to eq false
        end
      end

      context 'paranoid', paranoid: true do
        it 'sets scoped?' do
          data = @meta.evaluate(nil, 'entry')
          expect(data.scoped?).to eq true
        end
      end

      context 'evaluated' do
        let(:data) { @meta.evaluate('user', 'entry') }

        it 'sets relation' do
          expect(data.relation).to eq 'relation'
        end

        it 'sets access' do
          data.access.should == {
            update: {
              'field1' => nil,
              'field2' => nil,
              'field3' => 1,
              'field4' => 0..5,
              'field5' => l
            },
            read: {
              'field1' => nil,
              'field2' => nil,
              'field3' => nil
            }
          }
        end

        it 'marks destroyable' do
          expect(data.destroyable).to eq true
          expect(data.can?(:destroy)).to eq true
        end

        context 'marks updatable' do
          it 'with defaults' do
            expect(data.updatable?).to eq true
            expect(data.can?(:update)).to eq true
          end

          it 'respecting lambda', dev: true do
            expect(data.updatable?('field5' => 5)).to eq true
            expect(data.updatable?('field5' => 3)).to eq false
          end
        end

        it 'gets first unupdatable field' do
          data.first_unupdatable_field('field1' => 1, 'field6' => 2, 'field7' => 3).should == 'field6'
        end

        it 'marks creatable' do
          data.creatable?.should == false
          data.can?(:create).should == false
        end

        it 'gets first uncreatable field' do
          data.first_uncreatable_field('field1' => 1, 'field6' => 2).should == 'field1'
        end
      end
    end

    context 'deprecated methods' do
      before :each do
        @meta = Protector::DSL::Meta.new(nil, nil) { %w[field1 field2 field3] }

        @meta << lambda {
          can :view
          cannot :view, :field2
        }
      end

      it 'evaluates' do
        data = ActiveSupport::Deprecation.silence { @meta.evaluate('user', 'entry') }
        data.can?(:read).should == true
        data.can?(:read, :field1).should == true
        data.can?(:read, :field2).should == false
      end
    end

    context 'custom methods' do
      before :each do
        @meta = Protector::DSL::Meta.new(nil, nil) { %w[field1 field2] }

        @meta << lambda {
          can :drink, :field1
          can :eat
          cannot :eat, :field1
        }
      end

      it 'sets field-level restriction' do
        box = @meta.evaluate('user', 'entry')
        box.can?(:drink, :field1).should == true
        box.can?(:drink).should == true
      end

      it 'sets field-level protection' do
        box = @meta.evaluate('user', 'entry')
        box.can?(:eat, :field1).should == false
        box.can?(:eat).should == true
      end
    end

    it 'avoids lambdas recursion' do
      base = Class.new { include Protector::DSL::Base }
      meta = Protector::DSL::Meta.new(nil, nil) { %w[field1] }

      meta << lambda {
        can :create, field1: ->(x) { x.protector_subject?.should == false }
      }

      box = meta.evaluate('context', 'instance')
      box.creatable?('field1' => base.new.restrict!(nil))
    end
  end
end

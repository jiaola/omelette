describe Omelette::Importer::ToItemTypeStep do
  before :each do
    @step = Omelette::Importer::ToItemTypeStep.new('name', { if: lambda{ |x| x=='246'} }, nil)
  end
  describe '#can_process?' do
    it 'should use lambda to decide' do
      expect(@step.can_process?('246')).to eq true
      expect(@step.can_process?('135')).to eq false
    end
  end
end
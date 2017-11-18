require 'spec_helper'

describe Omelette::Util do
  describe '#build_elements_map' do
    it 'builds elements_map' do
      elements_map = Omelette::Util.build_elements_map 'www.example.com/api'
      expect(elements_map['Dublin Core']['Identifier']).to eq 43
    end
  end
end
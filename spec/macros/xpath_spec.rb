require 'nokogiri'

describe Omelette::Macros::Xpath do
  before :each do
    @xml_doc = Nokogiri::XML(file_fixture('person_tei.xml'))
    @aLambda = extract_xpath('//tei:TEI/@xml:id', tei: 'http://www.tei-c.org/ns/1.0')
  end

  it 'should create a lambda' do
    expect(@aLambda.respond_to? :call).to be true
  end

  it 'should get the value out of XML' do
    acc = []
    @aLambda.call(@xml_doc, acc)
    expect(acc.size).to eq 1
    expect(acc[0]).to eq 'DN00000247'
  end
end
require_relative './../test_helper'

class DecimalAttributeTest < MiniTest::Test

  def test_attribute_on_model_init
    b = Building.new price: 500.00
    assert_equal BigDecimal("500.0"), b.price
  end

  def test_attribute_as_string
    b = Building.new price: "500.00"
    assert_equal BigDecimal("500.0"), b.price
  end

end

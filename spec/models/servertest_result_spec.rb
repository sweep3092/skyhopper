#
# Copyright (c) 2013-2017 SKYARCH NETWORKS INC.
#
# This software is released under the MIT License.
#
# http://opensource.org/licenses/mit-license.php
#

require_relative '../spec_helper'

RSpec.describe ServertestResult, type: :model do
  it "is valid with valid attributes" do
    expect(ServertestResult.new).to be_valid
  end
end

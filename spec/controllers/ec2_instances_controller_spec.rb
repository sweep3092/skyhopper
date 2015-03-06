#
# Copyright (c) 2013-2015 SKYARCH NETWORKS INC.
#
# This software is released under the MIT License.
#
# http://opensource.org/licenses/mit-license.php
#

require_relative '../spec_helper'

describe Ec2InstancesController, :type => :controller do
  login_user

  let(:physical_id){'i-fugahoge'}
  let(:infra){create(:infrastructure)}

  describe '#change_scale' do
    let(:type){'t1.micro'}
    let(:req){post :change_scale, id: physical_id, infra_id: infra.id, instance_type: type}

    let(:instance){double(:instance,
      stop:                nil,
      status:              :stopped,
      instance_type:       type,
      :'instance_type=' => nil,
      start:               nil,
    )}
    before do
      allow_any_instance_of(Infrastructure).to receive_message_chain(:ec2, :instances, :[]).and_return(instance)
    end

    before{req}

    should_be_success

    it 'response should include instance_type' do
      expect(response.body).to be_include type
    end

    context 'when invalid instance_type' do
      let(:type){'hoge'}

      should_be_failure
    end
  end

  describe '#start' do
    let(:req){post :start, id: physical_id, infra_id: infra.id}

    let(:instance){double('instance', start: nil)}
    before do
      allow_any_instance_of(Infrastructure).to receive_message_chain(:ec2, :instances, :[]).and_return(instance)
      allow(Ec2InstancesController).to receive(:notify_ec2_status).with(instance, :running)
      req
    end

    should_be_success
  end

  describe '#stop' do
    let(:req){post :stop, id: physical_id, infra_id: infra.id}

    let(:instance){double('instance', stop: nil)}
    before do
      allow_any_instance_of(Infrastructure).to receive_message_chain(:ec2, :instances, :[]).and_return(instance)
      allow(Ec2InstancesController).to receive(:notify_ec2_status).with(instance, :stopped)
      req
    end

    should_be_success
  end

  describe '#reboot' do
    let(:req){post :reboot, id: physical_id, infra_id: infra.id}

    let(:instance){double('instance', reboot: nil)}
    before do
      allow_any_instance_of(Infrastructure).to receive_message_chain(:ec2, :instances, :[]).and_return(instance)
      req
    end

    should_be_success
  end

  describe '#serverspec_status' do
    let(:req){get :serverspec_status, id: physical_id, infra_id: infra.id}
    subject{JSON.parse(response.body)['status']}

    context 'when status failed' do
      before do
        Rails.cache.write(ServerspecStatus::TagName + physical_id, ServerspecStatus::Failed)
        req
      end

      should_be_success
      it{expect(subject).to be false}
    end

    [ServerspecStatus::Success, ServerspecStatus::Pending, ServerspecStatus::UnExecuted].each do |status|
      context "when status #{status}" do
        before do
          Rails.cache.write(ServerspecStatus::TagName + physical_id, status)
          req
        end

        should_be_success
        it{expect(subject).to be true}
      end
    end
  end
end

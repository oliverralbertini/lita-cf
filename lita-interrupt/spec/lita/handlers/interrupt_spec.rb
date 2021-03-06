# frozen_string_literal: true

require 'spec_helper'

describe Lita::Handlers::Interrupt, lita_handler: true do
  let(:maester) { Lita::User.create('U9298ANLQ', name: 'maester_luwin') }
  let(:sam) { Lita::User.create('U93MFAV9V', name: 'sam') }
  let(:arya) { Lita::User.create('U93FMA9VV', name: 'arya') }
  let(:jon) { Lita::User.create('U1BSCLVQ1', name: 'jon') }
  let(:tyrion) { Lita::User.create('U5062MBLE', name: 'tyrion') }
  let(:jaime) { Lita::User.create('U8FE4C6Z7', name: 'jaime') }
  let(:list) { Trello::List.new(list_details) }
  let(:interrupt_list) { Trello::List.new(interrupt_list_details) }
  let(:interrupt_card) { Trello::Card.new(interrupt_card_details) }
  let(:jaime_card) { Trello::Card.new(jaime_card_details) }
  let(:tyrion_card) { Trello::Card.new(tyrion_card_details) }
  let(:board_name) { 'Game of Boards' }
  let(:empty_hash) { {} }
  let(:redis_team_roster_hash) do
    JSON.parse(subject.redis.get(:roster_hash))
  end
  let(:add_team_members) do
    robot.auth.add_user_to_group!(maester, :team)
    send_command("add @#{jon.id} jonsnow", as: maester)
    send_command("add @#{sam.id} samwelltarley", as: maester)
    send_command("add @#{tyrion.id} tyrionlannister", as: maester)
    send_command("add @#{jaime.id} jaimelannister", as: maester)
  end
  let(:remove_team_members) do
    send_command("remove @#{jon.id}", as: maester)
    send_command("remove @#{sam.id}", as: maester)
    send_command("remove @#{tyrion.id}", as: maester)
    send_command("remove @#{jaime.id}", as: maester)
  end

  before do
    registry.configure do |config|
      config.robot.admins = [maester.id]
      config.handlers.interrupt.trello_developer_public_key = ''
      config.handlers.interrupt.trello_member_token = ''
      config.handlers.interrupt.board_name = board_name
    end
    allow(Trello::Member)
      .to receive(:find)
      .with('jonsnow')
      .and_return(Trello::Member.new(jon_details))
    allow(Trello::Member)
      .to receive(:find)
      .with('samwelltarley')
      .and_return(Trello::Member.new(sam_details))
    allow(Trello::Member)
      .to receive(:find)
      .with('jaimelannister')
      .and_return(Trello::Member.new(jaime_details))
    allow(Trello::Member)
      .to receive(:find)
      .with('tyrionlannister')
      .and_return(Trello::Member.new(tyrion_details))
    allow_any_instance_of(Trello::Member)
      .to receive(:boards)
      .and_return([Trello::Board.new(name: 'Game of Boards')])
    allow_any_instance_of(Trello::Board)
      .to receive(:lists)
      .and_return([list, interrupt_list])
    allow(Trello::List).to receive(:find).with(list.id).and_return(list)
    allow(Trello::List)
      .to receive(:find)
      .with(interrupt_list.id)
      .and_return(interrupt_list)
    allow(Trello::Card)
      .to receive(:find)
      .with(interrupt_card.id)
      .and_return(interrupt_card)
    allow(Trello::Card)
      .to receive(:find)
      .with(jaime_card.id)
      .and_return(jaime_card)
    allow(Trello::Card)
      .to receive(:find)
      .with(tyrion_card.id)
      .and_return(tyrion_card)
    allow(tyrion_card).to receive(:list).and_return(interrupt_list)
    allow(jaime_card).to receive(:list).and_return(interrupt_list)
    allow(interrupt_card).to receive(:list).and_return(interrupt_list)
    allow(list).to receive(:cards).and_return([tyrion_card, jaime_card])
    allow(interrupt_list)
      .to receive(:cards)
      .and_return([interrupt_card, tyrion_card, jaime_card])
    described_class.routes.clear
  end

  describe 'Routes:' do
    it { is_expected.to route_command('hey').to(:interrupt) }

    it { is_expected.to route(+"hi @#{robot.name} hey").to(:interrupt) }

    it { is_expected.to route_command(+'remove  me').to(:remove_from_team) }

    it { is_expected.to route_command(+'team').to(:list_team) }

    it do
      is_expected.not_to route_command(+'remove @someone').to(:remove_from_team)
    end

    it do
      is_expected
        .to route_command(+'remove @someone')
        .with_authorization_for(:team)
        .to(:remove_from_team)
    end

    it { is_expected.to route_command(+'add me trello_name').to(:add_to_team) }

    it do
      is_expected
        .not_to route_command(+'add @someone some_trello_user ')
        .to(:add_to_team)
    end

    it do
      is_expected
        .to route_command(+'add @someone some_trello_user ')
        .with_authorization_for(:team)
        .to(:add_to_team)
    end
  end

  describe 'Interruptions:' do
    before { add_team_members }

    context 'when there are multiple interrupt cards,' do
      before do
        allow(list)
          .to receive(:cards)
          .and_return([interrupt_card, tyrion_card, jaime_card])
      end
      it 'alerts the admins and pings the interrupt pair' do
        add_team_members
        send_command('hello hello hello', as: maester)
        expect(replies.last)
          .to eq(
            "<@#{tyrion.id}> <@#{jaime.id}>: "\
            "you have an interrupt from <@#{maester.id}> ^^"
          )
        expect(replies[-2])
          .to eq('Multiple interrupt cards found! Using first one.')
      end
    end

    context 'when tyrion & jaime are the interrupt pair,' do
      it 'looks up the interrupt list from the current interrupt card' do
        expect(Trello::Card)
          .to receive(:find)
          .with(interrupt_card.id)
          .and_return(interrupt_card)
        expect(interrupt_card)
          .to receive(:list)
          .and_return(interrupt_list)
        send_command('hey', as: maester)
      end

      context 'and the interrupt list contains the interrupt card,' do
        it 'pings the interrupt pair only' do
          send_command('hello hello hello', as: maester)
          expect(replies.last)
            .to eq(
              "<@#{tyrion.id}> <@#{jaime.id}>: "\
              "you have an interrupt from <@#{maester.id}> ^^"
            )
        end
      end
    end

    context 'when there is no interrupt list,' do
      before do
        allow_any_instance_of(Trello::List)
          .to receive(:cards).and_return([tyrion_card])
      end
      it "privately messages the robot's admins" do
        send_command('hello hello hello', as: maester)
        expect(replies.last).to eq(
          'Interrupt card not found! Your team '\
          'trello board needs a list with a card titled "Interrupt".'
        )
      end
    end

    context 'when there is nobody on the interrupt list,' do
      before do
        allow(interrupt_list).to receive(:cards).and_return([interrupt_card])
      end
      it 'pings the whole team' do
        send_command('hello hello hello', as: maester)
        expect(replies.last)
          .to eq(
            "<@#{jon.id}> <@#{sam.id}> <@#{tyrion.id}> <@#{jaime.id}>: "\
            "you have an interrupt from <@#{maester.id}> ^^"
          )
      end
    end

    context 'when the bot is mentioned but not commanded,' do
      it 'pings the interrupt pair' do
        send_message(+"hey hey hey @#{robot.name} hello", as: maester)
        expect(replies.last)
          .to eq(
            "<@#{tyrion.id}> <@#{jaime.id}>: "\
            "you have an interrupt from <@#{maester.id}> ^^"
          )
      end
    end

    context 'when the team board does not exist for any roster member,' do
      before do
        allow_any_instance_of(Trello::Member)
          .to receive(:boards)
          .and_return([Trello::Board.new(name: 'Game of Bards')])
      end
      it 'alerts the admins' do
        send_message(+"hey hey hey @#{robot.name} hello", as: maester)
        expect(replies.last)
          .to eq(
            %(Trello team board "#{board_name}" not found! )\
            'Set "TRELLO_BOARD_NAME" and restart me, please.'
          )
      end
    end

    context 'when there is no team roster,' do
      before { remove_team_members }

      context 'when someone triggers the interrupt,' do
        it 'lets the admins know that there is no roster' do
          send_command('hey', as: jon)
          expect(replies.last).to eq(
            'You must add some users to the team roster. '\
            "You will need each member's slack handle and trello user name."
          )
        end
      end
    end
  end

  describe 'Removing team members:' do
    before { add_team_members }

    context 'when someone requests to be removed from team roster,' do
      it 'removes them' do
        send_command('remove  me', as: sam)
        expect(replies.last)
          .to eq(
            %(Trello user "samwelltarley" (<@#{sam.id}>) removed!)
          )
        expect(redis_team_roster_hash).to eq(diminished_team_details)
      end
    end

    context 'when a teammate requests to remove someone from roster,' do
      it 'removes them' do
        robot.auth.add_user_to_group!(maester, :team)
        send_command("remove @#{sam.id} ", as: maester)
        expect(replies.last)
          .to eq(
            %(Trello user "samwelltarley" (<@#{sam.id}>) removed!)
          )
        expect(redis_team_roster_hash).to eq(diminished_team_details)
      end
    end

    context 'when a non-teammate requests to remove someone from roster,' do
      it 'does not remove them' do
        send_command("remove @#{sam.id} ", as: jaime)
        expect(replies.last)
          .to_not eq(
            %(Trello user "samwelltarley" (<@#{sam.id}>) removed!)
          )
        expect(redis_team_roster_hash).to eq(team_details)
      end
    end

    context 'when the roster is empty and an authorized user removes someone' do
      before { remove_team_members }

      it 'gives a helpful message' do
        send_command("remove @#{sam.id} ", as: maester)
        expect(replies.last).to eq('The team roster is empty at the moment.')
        expect(redis_team_roster_hash).to eq(empty_hash)
      end
    end
  end

  describe 'Adding team members:' do
    before { add_team_members }

    context 'when someone requests to be added to team roster,' do
      before do
        allow(Trello::Member)
          .to receive(:find)
          .with('aryastark')
          .and_return(Trello::Member.new(arya_details))
      end
      it 'adds them' do
        send_command('add me aryastark ', as: arya)
        expect(replies.last)
          .to eq(
            %(Trello user "aryastark" (<@#{arya.id}>) added!)
          )
        expect(redis_team_roster_hash).to eq(augmented_team_details)
      end
    end

    context 'when a teammate requests to add someone to the team roster,' do
      before do
        allow(Trello::Member)
          .to receive(:find)
          .with('aryastark')
          .and_return(Trello::Member.new(arya_details))
      end
      it 'adds them' do
        send_command("add @#{arya.id} aryastark", as: maester)
        expect(replies.last)
          .to eq(
            %(Trello user "aryastark" (<@#{arya.id}>) added!)
          )
        expect(redis_team_roster_hash).to eq(augmented_team_details)
      end
    end

    context 'when a non-teammate requests to add someone to the roster,' do
      before do
        allow(Trello::Member)
          .to receive(:find)
          .with('aryastark')
          .and_return(Trello::Member.new(arya_details))
      end
      it 'does not add them' do
        send_command("add @#{arya.id} aryastark", as: jaime)
        expect(replies.last)
          .to_not eq(
            %(Trello user "aryastark" (<@#{arya.id}>) added!)
          )
        expect(redis_team_roster_hash).to eq(team_details)
      end
    end

    context 'when someone tries to add a bogus trello user' do
      before do
        allow(Trello::Member)
          .to receive(:find)
          .with('aryasnark')
          .and_raise(Trello::Error.new('400'))
      end
      it 'does not add them but gives a useful message' do
        send_command("add @#{arya.id} aryasnark", as: maester)
        expect(replies.last)
          .to eq('Did not find the trello username "aryasnark"')
        expect(redis_team_roster_hash).to eq(team_details)
      end
    end
  end

  describe 'Listing team roster:' do
    context 'when the roster is empty and someone asks for the team roster,' do
      it 'notifies the user that the roster is empty' do
        send_command('team')
        expect(replies.last).to eq('The team roster is empty at the moment.')
      end
    end

    context 'when roster is populated and someone asks for the team roster,' do
      before { add_team_members }
      it 'lists the team member slack handles and trello user names' do
        send_command('team')
        expect(replies.last).to eq(
          'The team roster is <@U1BSCLVQ1> => jonsnow, '\
          '<@U93MFAV9V> => samwelltarley, '\
          '<@U5062MBLE> => tyrionlannister, '\
          '<@U8FE4C6Z7> => jaimelannister'
        )
      end
    end
  end
end

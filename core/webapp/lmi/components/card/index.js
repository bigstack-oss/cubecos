import React, { Component } from 'react';
import { Input } from 'antd';
import CardReactFormContainer from 'card-react';
import Form from '../uielements/form';
import isoModal from '../feedback/modal';
import CardCSS from './card.css';
import { CardInfoWrapper, InfoFormWrapper } from './cardModal.style';
import { InputWrapper } from '../uielements/styles/input.style';
import Modals from '../../containers/Feedback/Modal/modal.style';
import WithDirection from '../../config/withDirection';

const WDModal = Modals(isoModal);
const Modal = WithDirection(WDModal);

const InputField = InputWrapper(Input);

export default class extends Component {
  render() {
    const {
      modalType,
      editView,
      handleCancel,
      selectedCard,
      submitCard,
      updateCard
    } = this.props;

    this.columns = [
      {
        title: 'Number',
        dataIndex: 'number',
        key: 'number'
      },
      {
        title: 'Full Name',
        dataIndex: 'name',
        key: 'name'
      },
      {
        title: 'Expiry',
        dataIndex: 'expiry',
        key: 'expiry'
      },
      {
        title: 'CVC',
        dataIndex: 'cvc',
        key: 'cvc'
      }
    ];

    const saveButton = () => {
      submitCard();
    };
    const containerId = 'card-wrapper';
    const cardConfig = {
      container: containerId, // required an object contain the form inputs names. every input must have a unique name prop.
      formInputsNames: {
        number: 'number', // optional — default "number"
        expiry: 'expiry', // optional — default "expiry"
        cvc: 'cvc', // optional — default "cvc"
        name: 'name' // optional - default "name"
      },
      initialValues: selectedCard,
      classes: {
        valid: 'valid-input', // optional — default 'jp-card-valid'
        invalid: 'valid-input' // optional — default 'jp-card-invalid'
      },
      formatting: true, // optional - default true
      placeholders: {
        number: '•••• •••• •••• ••••',
        expiry: '••/••',
        cvc: '•••',
        name: 'Full Name'
      }
    };
    return (
      <div>
        <style>{CardCSS}</style>
        <Modal
          title={modalType === 'edit' ? 'Edit Card' : 'Add Card'}
          visible={editView}
          onCancel={handleCancel}
          cancelText="Cancel"
          onOk={saveButton}
          okText={modalType === 'edit' ? 'Edit Card' : 'Add Card'}
        >
          <CardInfoWrapper id={containerId} className="isoCardWrapper" />

          <CardReactFormContainer {...cardConfig}>
            <InfoFormWrapper>
              <Form className="isoCardInfoForm">
                {this.columns.map((column, index) => {
                  const { key, title } = column;
                  return (
                    <InputField
                      placeholder={title}
                      type="text"
                      className={`isoCardInput ${key}`}
                      onChange={event => {
                        selectedCard[key] = event.target.value;
                        updateCard(selectedCard);
                      }}
                      name={key}
                      key={index}
                    />
                  );
                })}
              </Form>
            </InfoFormWrapper>
          </CardReactFormContainer>
        </Modal>
      </div>
    );
  }
}

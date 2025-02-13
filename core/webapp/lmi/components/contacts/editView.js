import React, { Component } from 'react';
import { Icon } from 'antd';
import Input from '../uielements/input';
import Upload from '../uielements/upload';
import notification from '../notification';
import { ContactCardWrapper } from './contactCard.style';

function beforeUpload(file) {
  const isJPG = file.type === 'image/jpeg';
  if (!isJPG) {
    notification('error', 'You can only upload JPG file!', '');
    return false;
  }
  const isLt2M = file.size / 1024 / 1024 < 2;
  if (!isLt2M) {
    notification('error', 'Image must smaller than 2MB!', '');
    return false;
  }
  notification('success', 'Image uploaded successfully!', '');
  return true;
}
export default class extends Component {
  render() {
    const { contact, otherAttributes } = this.props;
    const name = contact.name ? contact.name : 'No Name';
    const extraInfos = [];
    const names = [
      { value: 'firstName', title: 'First Name' },
      { value: 'lastName', title: 'Last Name' }
    ];
    [...names, ...otherAttributes].forEach(attribute => {
      const value = contact[attribute.value];
      const editContact = event => {
        contact[attribute.value] = event.target.value;
        let name = '';
        if (contact.firstName) {
          name = `${contact.firstName} `;
        }
        if (contact.lastName) {
          name = `${name}${contact.lastName}`;
        }
        contact.name = name;
        this.props.editContact(contact);
      };
      if (attribute.value === 'note') {
        extraInfos.push(
          <div className="isoContactCardInfos" key={attribute.value}>
            <p className="isoInfoLabel">{`${attribute.title}`}</p>
            <Input
              placeholder={`${attribute.title}`}
              value={value}
              type="textarea"
              rows={5}
              onChange={event => editContact(event)}
            />
          </div>
        );
      } else {
        extraInfos.push(
          <div className="isoContactCardInfos" key={attribute.value}>
            <p className="isoInfoLabel">{`${attribute.title}`}</p>
            <Input
              placeholder={`${attribute.title}`}
              value={value}
              onChange={event => editContact(event)}
            />
          </div>
        );
      }
    });
    return (
      <ContactCardWrapper className="isoContactCard">
        <div className="isoContactCardHead">
          <div className="isoPersonImage">
            <Upload
              className="avatar-uploader"
              name="avatar"
              showUploadList={false}
              beforeUpload={beforeUpload}
              action=""
            >
              {contact.avatar ? (
                <img src={contact.avatar} alt="" className="avatar" />
              ) : (
                ''
              )}
              <Icon type="plus" className="avatar-uploader-trigger" />
            </Upload>
          </div>
          <h1 className="isoPersonName">{name}</h1>
        </div>
        <div className="isoContactInfoWrapper">{extraInfos}</div>
      </ContactCardWrapper>
    );
  }
}

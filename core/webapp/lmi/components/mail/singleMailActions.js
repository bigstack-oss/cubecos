import React, { Component } from 'react';
import Popover from '../uielements/popover';
import Popconfirm from '../feedback/popconfirm';
import notification from '../notification';
import { buckets } from './mailBuckets';
import { tags } from './mailTags';
import {
  SingleMailActions,
  MailActionsWrapper,
  MailCategoryWrapper,
  MailPaginationWrapper,
  MailActionDropdown
} from './singleMailActions.style';
import { rtl } from '../../config/withDirection';

class DeleteButton extends Component {
  render() {
    return (
      <Popconfirm
        title={`Sure to delete This mail?`}
        okText="DELETE"
        cancelText="No"
        onConfirm={() => {
          notification('error', `Deleted selected mail`, '');
        }}
      >
        <button type="button" className="mailDelete">
          <i className="ion-android-delete" />
        </button>
      </Popconfirm>
    );
  }
}

class MoveMailButton extends Component {
  render() {
    const bucketOptions = buckets.map(bucket => (
      <li
        onClick={() => {
          notification('success', `Massage Moved Successfully`, '');
        }}
        key={bucket}
      >
        {bucket}
      </li>
    ));
    const content = <MailActionDropdown>{bucketOptions}</MailActionDropdown>;
    return (
      <Popover
        title={`Move mail`}
        content={content}
        overlayClassName="mailMoveDropdown"
      >
        <button type="button" className="mailArchive">
          <i className="ion-android-folder" />
        </button>
      </Popover>
    );
  }
}

class SelectTagButton extends Component {
  render() {
    const tagOptions = tags.map(tag => (
      <li
        onClick={() => {
          notification('success', `Label Added`, '');
        }}
        key={tag}
      >
        {tag}
      </li>
    ));
    const content = <MailActionDropdown>{tagOptions}</MailActionDropdown>;
    return (
      <Popover
        title={`Select tag`}
        content={content}
        overlayClassName="mailMoveDropdown"
      >
        <button type="button" className="mailReport">
          <i className="ion-pricetags" />
        </button>
      </Popover>
    );
  }
}

export default class extends Component {
  render() {
    const { mail, filterMails, selectMail, toggleListVisible } = this.props;
    const index = filterMails.findIndex(
      filterMail => filterMail.id === mail.id
    );
    const toggleView = () => {
      toggleListVisible();
    };
    return (
      <SingleMailActions className="isoMailActionsController">
        {toggleListVisible ? (
          <button className="mailBackBtn" onClick={toggleView}>
            Inbox
          </button>
        ) : (
          ''
        )}
        <MailActionsWrapper className="isoMailActions">
          <button
            type="button"
            className="mailArchive"
            onClick={() => {
              notification('success', 'this mail archived');
            }}
          >
            <i className="ion-android-archive" />
          </button>

          <button
            type="button"
            className="mailReport"
            onClick={() => {
              notification('success', 'Reported as spam');
            }}
          >
            <i className="ion-android-alert" />
          </button>

          <DeleteButton />
        </MailActionsWrapper>

        <MailCategoryWrapper className="isoMailMove">
          <MoveMailButton />
          <SelectTagButton />
        </MailCategoryWrapper>

        <MailPaginationWrapper className="isoSingleMailPagination">
          {index === 0 ? (
            ''
          ) : (
            <button
              type="button"
              className="prevPage"
              onClick={() => selectMail(filterMails[index - 1].id)}
            >
              <i
                className={
                  rtl === 'rtl' ? 'ion-chevron-right' : 'ion-chevron-left'
                }
              />
            </button>
          )}

          {index + 1 === filterMails.length ? (
            ''
          ) : (
            <button
              type="button"
              className="nextPage"
              onClick={() => selectMail(filterMails[index + 1].id)}
            >
              <i
                className={
                  rtl === 'rtl' ? 'ion-chevron-left' : 'ion-chevron-right'
                }
              />
            </button>
          )}
        </MailPaginationWrapper>
      </SingleMailActions>
    );
  }
}

import React from 'react';
import { timeDifference } from '../../helpers/utility';
import { tags, tagColor } from './mailTags.js';
import MailListWrapper from './mailList.style';
import { rtl } from '../../config/withDirection';

export default function(mails, selectMail, selectedMail, toggleListVisible) {
  const renderSingleMail = (mail, key) => {
    const onClick = () => {
      selectMail(mail.id);
      if (toggleListVisible) {
        toggleListVisible();
      }
    };
    const isSelected = selectedMail === mail.id;
    const recpName = mail.name;
    const signature = {
      splitLet: recpName
        .match(/\b(\w)/g)
        .join('')
        .split('', 2)
    };
    const activeClass = isSelected ? 'activeMail' : '';
    const unreadClass = !mail.read ? 'unreadMail' : '';
    const tagOption = mail.tags
      ? tagColor[tags.findIndex(tags => tags === mail.tags)]
      : 'transparent';
    return (
      <div
        key={`list${key}`}
        onClick={onClick}
        className={`${activeClass} ${unreadClass} isoMailList`}
      >
        <span
          className="isoLabelIndicator"
          // style={{ borderTopColor: tagOption }}
          style={
            rtl === 'rtl' ? (
              { borderRightColor: tagOption }
            ) : (
              { borderTopColor: tagOption }
            )
          }
        />
        <div className="isoRecipentsImg">
          {mail.img ? (
            <img alt="#" src={mail.img} />
          ) : (
            <span>{signature.splitLet}</span>
          )}
        </div>

        <div className="isoMailInfo">
          <div className="infoHead">
            <p className="isoRecipents">{mail.name}</p>
            <span className="isoReceiveDate">{timeDifference(mail.date)}</span>
          </div>
          <p className="isoSubject">{mail.subject}</p>
          {/*<p className="isoDescription">{mail.body}</p>*/}
        </div>
      </div>
    );
  };
  return (
    <MailListWrapper className="isoMailListWrapper">
      {mails.map((mail, index) => renderSingleMail(mail, index))}
    </MailListWrapper>
  );
}

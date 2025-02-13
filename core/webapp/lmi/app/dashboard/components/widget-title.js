// dashboard/components/widget-title.js

import React from 'react';
import styled from 'styled-components';
import { palette } from 'styled-theme';
import createReactClass from 'create-react-class';

import Select, { SelectOption } from '../../../components/uielements/select';
import ContentHolder from '../../../components/utility/contentHolder';
const Option = SelectOption;

import { media } from '../../../config/style-util';
import IntlMessages from '../../../components/utility/intlMessages';

import Link from 'next/link';

const WidgetTitleDiv = styled.div`
  margin: 0 10px 20px 10px;

  display: flex;
  flex-direction: row;
  flex-wrap: nowrap;
  justify-content: flex-start;
  align-content: center;
  align-items: center;

  @media only screen and (max-width: 767) {
    margin-right: 0 !important;
  }
`;

const TitleDiv = styled.div`
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  padding: 0;
  flex: 1 1 auto;

  .widgetLabel {
    font-size: 15px;
    color: ${palette('text', 0)};
    font-weight: 600;
    line-height: 1;

    span {
        position: relative;
        top: 1px;
        padding-right: 5px;
        padding-left: 3px;
        opacity: 0.6;
        line-height: 1;
    }

    span + span {
      position: relative;
      top: 0px;
      padding-right: 8px;
      padding-left: 3px;
      opacity: 1;
      line-height: 1;
    }
  }

  .widgetAction {
    color: ${palette('text', 3)};
    padding-right: 14px;
    padding-top: 2px;
  }
`;

const SelectDiv = styled.div`
  .isoExampleWrapper {
    margin: -10px 0 5px 0 !important;
  }

  .ant-select-arrow {
    i {
      display: none;
    }
  }
`;

const TitleSelect = createReactClass({
  render: function() {
    const { id, def, options, selected, onSelect } = this.props;
    return (
      <SelectDiv>
        <ContentHolder>
          <Select defaultValue={selected} onChange={onSelect.bind(this, id)} style={{ width: '135px' }} >
            {options.map((item) =>
              <Option key={item[0]} value={item[0]} ><IntlMessages id={item[1]} /></Option>
            )}
          </Select>
        </ContentHolder>
      </SelectDiv>
    );
  }
});

const WidgetTitle = ({ label, icon, onClickUrl, selId, selDef, selOptions, selected, setWidgetTitleSel }) => {
  return (
    <WidgetTitleDiv>
      <TitleDiv>
        <h3 className="widgetLabel"><span className={icon}></span><IntlMessages id={label} /></h3>
        { selOptions && <TitleSelect id={selId} def={selDef} options={selOptions} selected={selected} onSelect={setWidgetTitleSel} /> }
        { onClickUrl && <Link href={onClickUrl}><a><span className='widgetAction ti-more-alt' /></a></Link> }
      </TitleDiv>
    </WidgetTitleDiv>
  );
}

export default WidgetTitle
import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../config/withDirection';

const ButtonWrapper = styled.div`
  display: flex;
  width: 100%;
  align-items: center;
  margin: 10px 0 30px;
`;

const CardInfoWrapper = styled.div`
  margin-bottom: 20px;

  .jp-card-container {
    margin: 40px auto 60px;
  }
`;

const WDInfoFormWrapper = styled.div`
  .isoCardInfoForm {
    display: flex;
    width: 100%;
    flex-wrap: wrap;

    .isoCardInput {
      margin-bottom: 10px;

      &.name {
        order: 2;
        margin-bottom: 0;
      }

      &.expiry,
      &.cvc {
        width: calc(100% / 2 - 5px);
      }

      &.expiry {
        color: #000000;
      }

      &::-webkit-input-placeholder {
      }

      &:-moz-placeholder {
      }

      &::-moz-placeholder {
      }
      &:-ms-input-placeholder {
      }
    }
  }
`;

const InfoFormWrapper = WithDirection(WDInfoFormWrapper);

export { ButtonWrapper, CardInfoWrapper, InfoFormWrapper };

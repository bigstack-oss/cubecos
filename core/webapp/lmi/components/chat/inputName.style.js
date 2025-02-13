import styled from "styled-components";
import { palette } from "styled-theme";

const UserItem = styled.div`
  display: flex;
  align-items: center;

  .userImg {
    width: 35px;
    height: 35px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    border-radius: 50%;
    margin-right: 15px;

    img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
  }

  .suggetionText {
    font-size: 13px;
    color: ${palette("text", 0)};
    font-weight: 500;
    margin: 0;
  }
`;

export default UserItem;

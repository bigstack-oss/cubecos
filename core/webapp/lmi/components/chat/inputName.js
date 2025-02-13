import React, { Component } from "react";
import AutoComplete, { AutoCompleteOption } from "../uielements/autocomplete";
import UserItem from "./inputName.style";

export default class extends Component {
  state = {
    value: "",
    result: []
  };

  handleSearch = value => {
    const result = [];
    if (value) {
      this.props.users.forEach(user => {
        if (user.name.toLowerCase().indexOf(value.toLowerCase()) > -1) {
          result.push(user);
        }
      });
    }
    this.setState({ result, value });
  };
  onSelect = id => {
    if (id) {
      this.state.result.forEach(user => {
        if (user.id === id) {
          this.setState({ value: user.name });
        }
      });
    }
  };
  render() {
    const { result, value } = this.state;
    return (
      <AutoComplete
        value={value}
        onSelect={this.onSelect}
        onSearch={this.handleSearch}
        placeholder="find your buddy"
        style={{ marginBottom: 10 }}
      >
        {result.map(user => (
          <AutoCompleteOption key={user.id} style={{ display: "flex" }}>
            <UserItem
              onClick={() => {
                this.setState({ value: user.name, result: [] });
                this.props.setComposedId(user.id);
              }}
            >
              <div className="userImg">
                <img alt="#" src={user.profileImageUrl} />
              </div>

              <span className="suggetionText">{user.name}</span>
            </UserItem>
          </AutoCompleteOption>
        ))}
      </AutoComplete>
    );
  }
}

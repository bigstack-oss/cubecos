import React, { Component } from "react";
import { connect } from "react-redux";
import { Row, Col } from "antd";
import PageHeader from "../../components/utility/pageHeader";
import Box from "../../components/utility/box";
import LayoutWrapper from "../../components/utility/layoutWrapper";
import { InputSearch } from "../../components/uielements/input";
import IntlMessages from "../../components/utility/intlMessages";
import notification from "../../components/notification";
import GitResult from "./githubResult";
import basicStyle from "../../config/basicStyle";
import actions from "../../redux/githubSearch/actions";

const { gitSearch, onPageChange } = actions;

class GitSearch extends Component {
	onSearch = value => {
		if (value && value.length > 0) {
			this.props.gitSearch(value);
		} else {
			notification("error", "Please type something");
		}
	};
	componentDidMount() {
		this.onSearch(this.props.GitSearch.searcText);
	}
	render() {
		const { rowStyle, colStyle, gutter } = basicStyle;
		const { onPageChange, GitSearch } = this.props;
		return (
			<LayoutWrapper>
				<PageHeader>
					<IntlMessages id="sidebar.githubSearch" />
				</PageHeader>
				<Row style={rowStyle} gutter={gutter} justify="start">
					<Col md={24} sm={24} xs={24} style={colStyle}>
						<Box>
							<InputSearch
								placeholder="Github Search"
								defaultValue={GitSearch.searcText}
								onSearch={this.onSearch}
							/>
							<GitResult
								GitSearch={GitSearch}
								defaultValue={GitSearch.searcText}
								onPageChange={onPageChange}
							/>
						</Box>
					</Col>
				</Row>
			</LayoutWrapper>
		);
	}
}
function mapStateToProps(state) {
	return { GitSearch: state.githubSearch };
}
export default connect(mapStateToProps, { gitSearch, onPageChange })(GitSearch);

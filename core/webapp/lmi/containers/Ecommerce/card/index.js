import React, { Component } from "react";
import { connect } from "react-redux";
import { Row, Col } from "antd";
import clone from "clone";
import Button from "../../../components/uielements/button";
import PageHeader from "../../../components/utility/pageHeader";
import Box from "../../../components/utility/box";
import LayoutWrapper from "../../../components/utility/layoutWrapper";
import Card from "../../../components/card";
import basicStyle from "../../../config/basicStyle";
import cardActions from "../../../redux/card/actions";
import { createColumns } from "./config";
import { ButtonWrapper } from "../../../components/card/cardModal.style";
import SimpleTable from "../../Tables/antTables/tableViews/simpleView";

const { addCard, editCard, deleteCard, restoreCards } = cardActions;
class Cards extends Component {
	constructor(props) {
		super(props);
		this.addColumn = this.addColumn.bind(this);
		this.editColumn = this.editColumn.bind(this);
		this.handleCancel = this.handleCancel.bind(this);
		this.submitCard = this.submitCard.bind(this);
		this.updateCard = this.updateCard.bind(this);

		this.columns = createColumns(this.editColumn, this.props.deleteCard);
		this.state = {
			editView: false,
			selectedCard: null,
			modalType: ""
		};
	}
	editColumn(card) {
		this.setState({
			editView: true,
			selectedCard: clone(card),
			modalType: "edit"
		});
	}
	addColumn() {
		this.setState({
			editView: true,
			selectedCard: {
				id: new Date().getTime(),
				key: new Date().getTime(),
				number: "",
				name: "",
				expiry: "",
				cvc: ""
			},
			modalType: "add"
		});
	}
	handleCancel() {
		this.setState({
			editView: false,
			selectedCard: null
		});
	}
	submitCard(card) {
		if (this.state.modalType === "edit") {
			this.props.editCard(this.state.selectedCard);
		} else {
			this.props.addCard(this.state.selectedCard);
		}
		this.setState({
			editView: false,
			selectedCard: null
		});
	}
	updateCard(selectedCard) {
		this.setState({ selectedCard });
	}
	render() {
		const { rowStyle, colStyle, gutter } = basicStyle;
		const { editView, selectedCard, modalType } = this.state;
		const cards = clone(this.props.cards);
		const createNumber = number => {
			const length = number.length;
			let newNumber = "";
			for (let i = 0; i < length - 4; i++) {
				newNumber = `*${newNumber}`;
			}
			for (let i = length - 4; i < length; i++) {
				newNumber = `${newNumber}${number.charAt(i)}`;
			}
			return newNumber;
		};
		cards.forEach((card, index) => {
			cards[index].number = createNumber(card.number);
		});
		return (
			<LayoutWrapper>
				<PageHeader>Cards</PageHeader>
				<Row style={rowStyle} gutter={gutter} justify="start">
					<Col md={24} sm={24} xs={24} style={colStyle}>
						<Box>
							<ButtonWrapper className="isoButtonWrapper">
								<Button type="primary" className="" onClick={this.addColumn}>
									Add New Card
								</Button>
							</ButtonWrapper>

							<SimpleTable columns={this.columns} dataSource={cards} />
							{selectedCard ? (
								<Card
									editView={editView}
									modalType={modalType}
									selectedCard={selectedCard}
									handleCancel={this.handleCancel}
									submitCard={this.submitCard}
									updateCard={this.updateCard}
								/>
							) : (
								""
							)}
						</Box>
					</Col>
				</Row>
			</LayoutWrapper>
		);
	}
}

function mapStateToProps(state) {
	return {
		...state.Cards
	};
}
export default connect(mapStateToProps, {
	addCard,
	editCard,
	deleteCard,
	restoreCards
})(Cards);

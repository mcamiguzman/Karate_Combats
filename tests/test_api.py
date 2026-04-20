import pytest
from unittest.mock import patch, MagicMock
from api.app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_index(client):
    with patch("api.app.get_db") as mock_db:
        mock_conn = MagicMock()
        mock_cursor = MagicMock()

        mock_conn.cursor.return_value = mock_cursor
        mock_cursor.fetchall.return_value = []

        mock_db.return_value = mock_conn

        response = client.get("/")
        assert response.status_code == 200


def test_create_combat(client):
    with patch("api.app.send_to_queue") as mock_queue, \
         patch("api.app.get_db") as mock_db:

        # Mock DB
        mock_conn = MagicMock()
        mock_cursor = MagicMock()

        mock_conn.cursor.return_value = mock_cursor
        mock_cursor.fetchall.return_value = []

        mock_db.return_value = mock_conn

        response = client.post("/combats", data={
            "time": "10:00",
            "red": "A",
            "blue": "B",
            "points_red": 1,
            "points_blue": 2,
            "fouls_red": 0,
            "fouls_blue": 0,
            "judges": "3"
        })

        # Verificaciones
        assert response.status_code == 200
        mock_queue.assert_called_once()
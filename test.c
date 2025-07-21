#include <stdio.h>
#define N 15
#define M 13

void transform(int *buf, int **matr, int n, int m);
void make_picture(int **picture, int n, int m);
void reset_picture(int **picture, int n, int m);

int main() {
  int picture_data[N][M];
  int *picture[N];
  transform((int *)picture_data, picture, N, M);
  make_picture(picture, N, M);
  for (int i = 0; i < N; i++) {
    for (int j = 0; j < M; j++) {
      printf("%d ", picture[i][j]);
    }
    printf("\n");
  }
  return 0;
}

void make_picture(int **picture, int n, int m) {
  int frame_w[] = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
  int frame_h[] = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
  int tree_trunk[] = {7, 7, 7, 7};
  int tree_foliage[] = {3, 3, 3, 3};
  int sun_data[6][5] = {{0, 6, 6, 6, 6}, {0, 0, 6, 6, 6}, {0, 0, 6, 6, 6},
                        {0, 6, 0, 0, 6}, {0, 0, 0, 0, 0}, {0, 0, 0, 0, 0}};
  reset_picture(picture, n, m);
  for (int j = 0; j < m; j++) {
    picture[0][j] = frame_w[j];
    picture[n - 1][j] = frame_w[j];
  }
  for (int i = 0; i < n; i++) {
    picture[i][0] = frame_h[i];
    picture[i][m - 1] = frame_h[i];
  }
  for (int j = 0; j < m; j++)
    picture[7][j] = 1;
  for (int i = 1; i < n - 1; i++)
    if (i != 7)
      picture[i][6] = 1;
  int foliage_pos[12][2] = {{2, 3}, {2, 4}, {3, 2}, {3, 3}, {3, 4}, {3, 5},
                            {4, 2}, {4, 3}, {4, 4}, {4, 5}, {5, 3}, {5, 4}};
  for (int k = 0; k < 12; k++)
    picture[foliage_pos[k][0]][foliage_pos[k][1]] = 3;
  int trunk_pos[10][2] = {{6, 3}, {6, 4},  {8, 3},  {8, 4},  {9, 3},
                          {9, 4}, {10, 2}, {10, 3}, {10, 4}, {10, 5}};
  for (int k = 0; k < 10; k++)
    picture[trunk_pos[k][0]][trunk_pos[k][1]] = 7;
  for (int i = 0; i < 6; i++)
    for (int j = 0; j < 5; j++)
      picture[i + 1][j + 7] = sun_data[i][j];
}

void reset_picture(int **picture, int n, int m) {
  for (int i = 0; i < n; i++)
    for (int j = 0; j < m; j++)
      picture[i][j] = 0;
}

void transform(int *buf, int **matr, int n, int m) {
  for (int i = 0; i < n; i++)
    matr[i] = buf + i * m;
}
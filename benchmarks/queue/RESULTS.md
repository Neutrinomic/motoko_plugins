# Queue: full instruction and allocation results

Core Queue 2.6.2 versus the final plugin. Three fresh-canister trials per implementation/case; every instruction and allocation count matched across all three trials. These are whole measured-operation totals, including the benchmark loop and checksum. A ratio above 1 means fewer plugin instructions. Allocation is not live memory. See [methodology and retained-memory results](README.md).

## Size 0

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 339 | 346 | 0.98× | 0 | 0 |
| `push_front` | 369 | 376 | 0.98× | 0 | 0 |
| `pop_front` | 399 | 406 | 0.98× | 0 | 0 |
| `pop_back` | 429 | 436 | 0.98× | 0 | 0 |
| `peek_front` | 741 | 753 | 0.98× | 0 | 0 |
| `peek_back` | 771 | 783 | 0.98× | 0 | 0 |
| `fifo_churn` | 1,675,783 | 1,479,210 | 1.13× | 98,304 | 440 |
| `lifo_churn` | 1,675,813 | 1,419,848 | 1.18× | 98,304 | 440 |
| `both_ends_churn` | 1,744,963 | 1,548,390 | 1.13× | 98,304 | 440 |
| `values` | 1,159 | 1,838 | 0.63× | 96 | 232 |
| `reverse_values` | 1,733 | 1,868 | 0.93× | 192 | 232 |
| `from_array` | 1,443 | 2,355 | 0.61× | 120 | 304 |
| `to_array` | 1,672 | 1,193 | 1.40× | 160 | 24 |
| `clone` | 2,061 | 2,894 | 0.71× | 216 | 384 |

## Size 1

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 1,307 | 3,002 | 0.44× | 96 | 440 |
| `push_front` | 1,337 | 3,090 | 0.43× | 96 | 440 |
| `pop_front` | 1,097 | 1,298 | 0.85× | 0 | 0 |
| `pop_back` | 1,127 | 1,270 | 0.89× | 0 | 0 |
| `peek_front` | 814 | 934 | 0.87× | 0 | 0 |
| `peek_back` | 844 | 968 | 0.87× | 0 | 0 |
| `fifo_churn` | 1,715,719 | 1,370,638 | 1.25× | 98,304 | 0 |
| `lifo_churn` | 1,715,749 | 1,311,276 | 1.31× | 98,304 | 0 |
| `both_ends_churn` | 1,784,899 | 1,439,818 | 1.24× | 98,304 | 0 |
| `values` | 1,428 | 2,435 | 0.59× | 96 | 232 |
| `reverse_values` | 2,272 | 2,471 | 0.92× | 232 | 232 |
| `from_array` | 2,308 | 5,094 | 0.45× | 216 | 744 |
| `to_array` | 2,132 | 1,650 | 1.29× | 168 | 32 |
| `clone` | 3,089 | 5,938 | 0.52× | 312 | 824 |

## Size 4

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 4,286 | 4,742 | 0.90× | 384 | 440 |
| `push_front` | 4,316 | 5,004 | 0.86× | 384 | 440 |
| `pop_front` | 3,233 | 3,662 | 0.88× | 0 | 0 |
| `pop_back` | 3,263 | 3,460 | 0.94× | 0 | 0 |
| `peek_front` | 1,879 | 2,338 | 0.80× | 0 | 0 |
| `peek_back` | 1,909 | 2,384 | 0.80× | 0 | 0 |
| `fifo_churn` | 1,715,719 | 1,370,638 | 1.25× | 98,304 | 0 |
| `lifo_churn` | 1,715,749 | 1,311,276 | 1.31× | 98,304 | 0 |
| `both_ends_churn` | 1,784,899 | 1,439,818 | 1.24× | 98,304 | 0 |
| `values` | 2,235 | 3,380 | 0.66× | 96 | 232 |
| `reverse_values` | 3,889 | 3,416 | 1.14× | 352 | 232 |
| `from_array` | 4,990 | 7,083 | 0.70× | 504 | 744 |
| `to_array` | 2,948 | 1,896 | 1.55× | 192 | 56 |
| `clone` | 6,248 | 7,996 | 0.78× | 600 | 824 |

## Size 16

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 16,202 | 11,702 | 1.38× | 1,536 | 440 |
| `push_front` | 16,232 | 12,660 | 1.28× | 1,536 | 440 |
| `pop_front` | 11,777 | 13,118 | 0.90× | 0 | 0 |
| `pop_back` | 11,807 | 12,220 | 0.97× | 0 | 0 |
| `peek_front` | 6,139 | 7,954 | 0.77× | 0 | 0 |
| `peek_back` | 6,169 | 8,048 | 0.77× | 0 | 0 |
| `fifo_churn` | 1,715,719 | 1,370,638 | 1.25× | 98,304 | 0 |
| `lifo_churn` | 1,715,749 | 1,311,276 | 1.31× | 98,304 | 0 |
| `both_ends_churn` | 1,784,899 | 1,439,818 | 1.24× | 98,304 | 0 |
| `values` | 5,463 | 7,160 | 0.76× | 96 | 232 |
| `reverse_values` | 10,357 | 7,196 | 1.44× | 832 | 232 |
| `from_array` | 15,718 | 15,039 | 1.05× | 1,656 | 744 |
| `to_array` | 6,212 | 2,880 | 2.16× | 288 | 152 |
| `clone` | 18,884 | 16,228 | 1.16× | 1,752 | 824 |

## Size 31

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 31,097 | 20,402 | 1.52× | 2,976 | 440 |
| `push_front` | 31,127 | 22,230 | 1.40× | 2,976 | 440 |
| `pop_front` | 22,457 | 24,938 | 0.90× | 0 | 0 |
| `pop_back` | 22,487 | 23,170 | 0.97× | 0 | 0 |
| `peek_front` | 11,464 | 14,974 | 0.77× | 0 | 0 |
| `peek_back` | 11,494 | 15,128 | 0.76× | 0 | 0 |
| `fifo_churn` | 1,715,719 | 1,370,638 | 1.25× | 98,304 | 0 |
| `lifo_churn` | 1,715,749 | 1,311,276 | 1.31× | 98,304 | 0 |
| `both_ends_churn` | 1,784,899 | 1,439,818 | 1.24× | 98,304 | 0 |
| `values` | 9,498 | 11,885 | 0.80× | 96 | 232 |
| `reverse_values` | 18,442 | 11,921 | 1.55× | 1,432 | 232 |
| `from_array` | 29,128 | 24,984 | 1.17× | 3,096 | 744 |
| `to_array` | 10,292 | 4,110 | 2.50× | 408 | 272 |
| `clone` | 34,679 | 26,518 | 1.31× | 3,192 | 824 |

## Size 32

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 32,090 | 20,982 | 1.53× | 3,072 | 440 |
| `push_front` | 32,120 | 22,868 | 1.40× | 3,072 | 440 |
| `pop_front` | 23,169 | 25,726 | 0.90× | 0 | 0 |
| `pop_back` | 23,199 | 23,900 | 0.97× | 0 | 0 |
| `peek_front` | 11,819 | 15,442 | 0.77× | 0 | 0 |
| `peek_back` | 11,849 | 15,600 | 0.76× | 0 | 0 |
| `fifo_churn` | 1,715,719 | 1,391,654 | 1.23× | 98,304 | 440 |
| `lifo_churn` | 1,715,749 | 1,924,516 | 0.89× | 98,304 | 440 |
| `both_ends_churn` | 1,784,899 | 1,747,394 | 1.02× | 98,304 | 440 |
| `values` | 9,767 | 12,200 | 0.80× | 96 | 232 |
| `reverse_values` | 18,981 | 12,236 | 1.55× | 1,472 | 232 |
| `from_array` | 30,022 | 25,647 | 1.17× | 3,192 | 744 |
| `to_array` | 10,564 | 4,192 | 2.52× | 416 | 280 |
| `clone` | 35,732 | 27,204 | 1.31× | 3,288 | 824 |

## Size 33

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 33,083 | 23,747 | 1.39× | 3,168 | 880 |
| `push_front` | 33,113 | 25,691 | 1.29× | 3,168 | 880 |
| `pop_front` | 23,881 | 26,838 | 0.89× | 0 | 0 |
| `pop_back` | 23,911 | 24,954 | 0.96× | 0 | 0 |
| `peek_front` | 12,174 | 15,910 | 0.77× | 0 | 0 |
| `peek_back` | 12,204 | 16,072 | 0.76× | 0 | 0 |
| `fifo_churn` | 1,715,719 | 1,391,654 | 1.23× | 98,304 | 440 |
| `lifo_churn` | 1,715,749 | 1,311,276 | 1.31× | 98,304 | 0 |
| `both_ends_churn` | 1,784,899 | 2,053,058 | 0.87× | 98,304 | 440 |
| `values` | 10,036 | 12,797 | 0.78× | 96 | 232 |
| `reverse_values` | 19,520 | 12,839 | 1.52× | 1,512 | 232 |
| `from_array` | 30,916 | 28,495 | 1.08× | 3,288 | 1,184 |
| `to_array` | 10,836 | 4,461 | 2.43× | 424 | 288 |
| `clone` | 36,785 | 30,357 | 1.21× | 3,384 | 1,264 |

## Size 1,000

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 993,314 | 650,157 | 1.53× | 96,000 | 14,080 |
| `push_front` | 993,344 | 708,187 | 1.40× | 96,000 | 14,080 |
| `pop_front` | 712,385 | 798,554 | 0.89× | 0 | 0 |
| `pop_back` | 712,415 | 740,584 | 0.96× | 0 | 0 |
| `peek_front` | 355,459 | 468,466 | 0.76× | 0 | 0 |
| `peek_back` | 355,489 | 472,496 | 0.75× | 0 | 0 |
| `fifo_churn` | 1,715,719 | 1,391,654 | 1.23× | 98,304 | 440 |
| `lifo_churn` | 1,715,749 | 1,311,276 | 1.31× | 98,304 | 0 |
| `both_ends_churn` | 1,784,899 | 1,747,394 | 1.02× | 98,304 | 440 |
| `values` | 270,159 | 325,862 | 0.83× | 96 | 232 |
| `reverse_values` | 540,733 | 326,084 | 1.66× | 40,192 | 232 |
| `from_array` | 895,414 | 735,166 | 1.22× | 96,120 | 14,384 |
| `to_array` | 273,860 | 89,365 | 3.06× | 8,160 | 8,024 |
| `clone` | 1,055,036 | 767,729 | 1.37× | 96,216 | 14,464 |

## Size 10,000

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 9,930,314 | 6,484,142 | 1.53× | 960,000 | 137,720 |
| `push_front` | 9,930,344 | 7,064,172 | 1.41× | 960,000 | 137,720 |
| `pop_front` | 7,120,385 | 7,981,598 | 0.89× | 0 | 0 |
| `pop_back` | 7,120,415 | 7,401,628 | 0.96× | 0 | 0 |
| `peek_front` | 3,550,459 | 4,680,466 | 0.76× | 0 | 0 |
| `peek_back` | 3,550,489 | 4,720,496 | 0.75× | 0 | 0 |
| `fifo_churn` | 16,750,519 | 13,568,702 | 1.23× | 960,000 | 440 |
| `lifo_churn` | 16,750,549 | 12,800,556 | 1.31× | 960,000 | 0 |
| `both_ends_churn` | 17,425,579 | 17,042,498 | 1.02× | 960,000 | 440 |
| `values` | 2,691,159 | 3,240,104 | 0.83× | 96 | 232 |
| `reverse_values` | 5,391,733 | 3,242,012 | 1.66× | 400,192 | 232 |
| `from_array` | 8,941,414 | 7,316,151 | 1.22× | 960,120 | 138,024 |
| `to_array` | 2,721,860 | 879,912 | 3.09× | 80,160 | 80,024 |
| `clone` | 10,532,036 | 7,634,956 | 1.38× | 960,216 | 138,104 |

## Size 100,000

| Operation | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` | 99,300,314 | 64,828,362 | 1.53× | 9,600,000 | 1,375,000 |
| `push_front` | 99,300,344 | 70,628,392 | 1.41× | 9,600,000 | 1,375,000 |
| `pop_front` | 71,200,385 | 79,812,686 | 0.89× | 0 | 0 |
| `pop_back` | 71,200,415 | 74,012,716 | 0.96× | 0 | 0 |
| `peek_front` | 35,500,459 | 46,800,466 | 0.76× | 0 | 0 |
| `peek_back` | 35,500,489 | 47,200,496 | 0.75× | 0 | 0 |
| `fifo_churn` | 167,500,519 | 135,668,063 | 1.23× | 9,600,000 | 440 |
| `lifo_churn` | 167,500,549 | 187,702,468 | 0.89× | 9,600,000 | 440 |
| `both_ends_churn` | 174,250,579 | 170,402,498 | 1.02× | 9,600,000 | 440 |
| `values` | 26,901,159 | 32,383,088 | 0.83× | 96 | 232 |
| `reverse_values` | 53,901,733 | 32,401,868 | 1.66× | 4,000,192 | 232 |
| `from_array` | 89,401,414 | 73,130,371 | 1.22× | 9,600,120 | 1,375,304 |
| `to_array` | 27,201,860 | 8,785,756 | 3.10× | 800,160 | 800,024 |
| `clone` | 105,302,036 | 76,312,160 | 1.38× | 9,600,216 | 1,375,384 |
